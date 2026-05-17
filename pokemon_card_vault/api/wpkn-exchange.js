const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  calculateQuote,
  findWpknDeposit,
  maybeSendWpkn,
  normalizeAddress,
  normalizeDirection,
  pancakeSpotPrice,
  publicQuote,
  reserveSnapshot,
  settlementMode,
} = require('../server/_wpkn_exchange');

function serialize(doc) {
  const data = doc.data() || {};
  return {
    requestId: doc.id,
    direction: data.direction || '',
    amountIn: Number(data.amountIn || 0),
    amountOutQuoted: Number(data.amountOutQuoted || 0),
    feePknOrWpkn: Number(data.feePknOrWpkn || 0),
    fromAsset: data.fromAsset || '',
    toAsset: data.toAsset || '',
    toAddress: data.toAddress || '',
    depositTxHash: data.depositTxHash || null,
    payoutTxHash: data.payoutTxHash || null,
    status: data.status || 'pending_deposit_or_lock',
    settlementMode: data.settlementMode || 'manual_pending',
    createdAt: data.createdAt?.toDate?.().toISOString?.() || null,
    updatedAt: data.updatedAt?.toDate?.().toISOString?.() || null,
  };
}

async function handleQuote(req, res, decoded, admin, firestore) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const [reserves, marketPrice] = await Promise.all([
    reserveSnapshot(firestore),
    pancakeSpotPrice(),
  ]);
  const quote = calculateQuote({
    direction: req.body?.direction,
    amountIn: req.body?.amountIn,
    reserves,
    marketPrice,
  });
  const now = admin.firestore.FieldValue.serverTimestamp();
  const quoteRef = firestore.collection('wpkn_exchange_quotes').doc();

  await quoteRef.set({
    ...quote,
    uid: decoded.uid,
    status: 'quoted',
    createdAt: now,
    updatedAt: now,
    quoteExpiresAtMs: Date.parse(quote.quoteExpiresAt),
  });

  return res.status(200).json(publicQuote(quoteRef.id, quote));
}

async function handleStatus(req, res, decoded, firestore) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const requestId = String(req.query.requestId || '').trim();

  if (requestId) {
    const doc = await firestore.collection('wpkn_exchange_requests').doc(requestId).get();
    if (!doc.exists || doc.data()?.uid !== decoded.uid) {
      return res.status(404).json({ error: 'Exchange request was not found.' });
    }
    return res.status(200).json({ request: serialize(doc) });
  }

  const snapshot = await firestore
    .collection('wpkn_exchange_requests')
    .where('uid', '==', decoded.uid)
    .get();
  const requests = snapshot.docs
    .map(serialize)
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')))
    .slice(0, 12);

  return res.status(200).json({
    requests,
  });
}

async function handleRequest(req, res, decoded, admin, firestore) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const quoteId = String(req.body?.quoteId || '').trim();
  const direction = normalizeDirection(req.body?.direction);
  const payoutAddress = normalizeAddress(
    req.body?.toAddress,
    direction === 'pkn_to_wpkn'
      ? 'Enter a valid BSC payout address.'
      : 'Enter a valid PKN payout address.',
  );

  if (!quoteId) {
    return res.status(400).json({ error: 'Quote id is required.' });
  }

  const quoteRef = firestore.collection('wpkn_exchange_quotes').doc(quoteId);
  const requestRef = firestore.collection('wpkn_exchange_requests').doc();
  const balanceRef = firestore.collection('balances').doc(decoded.uid);
  const userRef = firestore.collection('users').doc(decoded.uid);
  const ledgerRef = firestore.collection('ledger_entries').doc();
  let depositRef = null;
  let verifiedDeposit = null;
  let requestPayload = null;

  await firestore.runTransaction(async (transaction) => {
    const quoteDoc = await transaction.get(quoteRef);
    if (!quoteDoc.exists) {
      throw Object.assign(new Error('Exchange quote was not found.'), { statusCode: 404 });
    }
    const quote = quoteDoc.data() || {};
    if (quote.uid !== decoded.uid) {
      throw Object.assign(new Error('This quote belongs to another user.'), { statusCode: 403 });
    }
    if (quote.status !== 'quoted') {
      throw Object.assign(new Error('This quote has already been used.'), { statusCode: 409 });
    }
    if (quote.direction !== direction) {
      throw Object.assign(new Error('Quote direction does not match request.'), {
        statusCode: 400,
      });
    }
    if (
      direction === 'wpkn_to_pkn' &&
      Number(verifiedDeposit.amountWpkn || 0) < Number(quote.amountIn || 0)
    ) {
      throw Object.assign(new Error('Deposit amount is lower than the quoted wPKN amount.'), {
        statusCode: 400,
      });
    }
    if (Date.now() > Number(quote.quoteExpiresAtMs || 0)) {
      transaction.update(quoteRef, {
        status: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw Object.assign(new Error('Exchange quote expired. Request a new quote.'), {
        statusCode: 410,
      });
    }

    const userDoc = await transaction.get(userRef);
    const username = String(userDoc.data()?.username || '').trim().toLowerCase();
    const linkedWallet = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
    if (direction === 'wpkn_to_pkn') {
      if (!linkedWallet) {
        throw Object.assign(
          new Error('Link the BSC wallet that sent the wPKN deposit before requesting payout.'),
          { statusCode: 400 },
        );
      }
      const usedDeposits = await transaction.get(
        firestore.collection('wpkn_exchange_deposits').where('fromAddress', '==', linkedWallet).limit(50),
      );
      verifiedDeposit = await findWpknDeposit({
        fromAddress: linkedWallet,
        expectedAmountWpkn: Number(quote.amountIn || 0),
        usedTxHashes: usedDeposits.docs.map((doc) => doc.id),
      });
      depositRef = firestore.collection('wpkn_exchange_deposits').doc(verifiedDeposit.txHash);
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const baseRequest = {
      uid: decoded.uid,
      email: String(decoded.email || '').trim().toLowerCase(),
      username,
      quoteId,
      direction,
      amountIn: Number(quote.amountIn || 0),
      amountOutQuoted: Number(quote.amountOut || 0),
      feePknOrWpkn: Number(quote.feeAmount || 0),
      fromAsset: quote.fromAsset,
      toAsset: quote.toAsset,
      toAddress: payoutAddress,
      depositTxHash: direction === 'wpkn_to_pkn' ? verifiedDeposit.txHash : null,
      payoutTxHash: null,
      settlementMode: settlementMode(),
      status: direction === 'pkn_to_wpkn' ? 'locked' : 'pending_deposit_or_lock',
      quoteExpiresAt: quote.quoteExpiresAt,
      createdAt: now,
      updatedAt: now,
    };

    if (direction === 'pkn_to_wpkn') {
      const balanceDoc = await transaction.get(balanceRef);
      const available = Number(balanceDoc.data()?.availablePkn || 0);
      if (available < baseRequest.amountIn) {
        throw Object.assign(new Error('Your site balance is too low.'), { statusCode: 400 });
      }
      transaction.set(
        balanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(-baseRequest.amountIn),
          lockedPkn: admin.firestore.FieldValue.increment(baseRequest.amountIn),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(ledgerRef, {
        uid: decoded.uid,
        type: 'wpkn_exchange_pkn_locked',
        amountPkn: -baseRequest.amountIn,
        wpknExchangeRequestId: requestRef.id,
        toAddress: payoutAddress,
        createdAt: now,
      });
    } else {
      const depositDoc = await transaction.get(depositRef);
      if (depositDoc.exists) {
        throw Object.assign(new Error('This wPKN deposit tx was already used.'), {
          statusCode: 409,
        });
      }
      baseRequest.status = 'completed';
      baseRequest.settlementMode = 'automatic_available';
      baseRequest.completedAt = now;
      transaction.set(
        balanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(baseRequest.amountOutQuoted),
          lockedPkn: admin.firestore.FieldValue.increment(0),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(depositRef, {
        uid: decoded.uid,
        requestId: requestRef.id,
        txHash: verifiedDeposit.txHash,
        fromAddress: verifiedDeposit.fromAddress,
        amountWpkn: verifiedDeposit.amountWpkn,
        createdAt: now,
      });
      transaction.set(ledgerRef, {
        uid: decoded.uid,
        type: 'wpkn_exchange_pkn_credited',
        amountPkn: baseRequest.amountOutQuoted,
        wpknExchangeRequestId: requestRef.id,
        depositTxHash: verifiedDeposit.txHash,
        fromAddress: verifiedDeposit.fromAddress,
        createdAt: now,
      });
    }

    transaction.set(requestRef, baseRequest);
    transaction.update(quoteRef, {
      status: direction === 'wpkn_to_pkn' ? 'completed' : 'pending_deposit_or_lock',
      requestId: requestRef.id,
      updatedAt: now,
    });
    requestPayload = baseRequest;
  });

  let settlement = {
    mode: requestPayload.settlementMode,
    txHash: direction === 'wpkn_to_pkn' ? verifiedDeposit.txHash : null,
  };
  if (direction === 'pkn_to_wpkn') {
    try {
      settlement = await maybeSendWpkn({
        toAddress: payoutAddress,
        amountWpkn: requestPayload.amountOutQuoted,
      });
    } catch (settlementError) {
      settlement = { mode: 'manual_pending', txHash: null };
      await requestRef.set(
        {
          status: 'locked',
          settlementMode: 'manual_pending',
          settlementError: settlementError.message || 'Automatic settlement failed.',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    if (settlement.txHash) {
      await requestRef.set(
        {
          status: 'processing',
          payoutTxHash: settlement.txHash,
          settlementMode: settlement.mode,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  }

  return res.status(200).json({
    ok: true,
    requestId: requestRef.id,
    status:
      direction === 'wpkn_to_pkn'
        ? 'completed'
        : settlement.txHash
          ? 'processing'
          : requestPayload.status,
    settlementMode: settlement.mode,
    payoutTxHash: settlement.txHash,
    quote: publicQuote(quoteId, {
      direction: requestPayload.direction,
      fromAsset: requestPayload.fromAsset,
      toAsset: requestPayload.toAsset,
      amountIn: requestPayload.amountIn,
      amountOut: requestPayload.amountOutQuoted,
      feeAmount: requestPayload.feePknOrWpkn,
      marketPrice: 1,
      spreadBps: 0,
      inventoryBps: 0,
      sizeImpactBps: 0,
      totalCostBps: 0,
      quoteExpiresAt: requestPayload.quoteExpiresAt,
      settlementMode: requestPayload.settlementMode,
    }),
  });
}

module.exports = async function handler(req, res) {
  try {
    const action = String(req.query.action || req.body?.action || '').trim();
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();

    if (action === 'quote') {
      return handleQuote(req, res, decoded, admin, firestore);
    }
    if (action === 'request') {
      return handleRequest(req, res, decoded, admin, firestore);
    }
    if (action === 'status') {
      return handleStatus(req, res, decoded, firestore);
    }

    return res.status(404).json({ error: 'Exchange action was not found.' });
  } catch (error) {
    console.error('wpkn-exchange failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Exchange request failed.',
    });
  }
};
