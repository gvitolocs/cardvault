const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  CHAIN_CONFIG,
  calculateCryptoPknQuote,
  normalizeAddress,
  normalizeAsset,
  publicCryptoPknQuote,
  verifyCryptoDeposit,
} = require('../server/_crypto_pkn_purchase');

function serialize(doc) {
  const data = doc.data() || {};
  return {
    requestId: doc.id,
    quoteId: data.quoteId || '',
    fromAsset: data.fromAsset || '',
    toAsset: data.toAsset || 'PKN',
    amountIn: Number(data.amountIn || 0),
    amountOut: Number(data.amountOut || 0),
    depositTxHash: data.depositTxHash || null,
    fromAddress: data.fromAddress || '',
    status: data.status || 'pending',
    chainId: Number(data.chainId || 0),
    chainName: data.chainName || '',
    createdAt: data.createdAt?.toDate?.().toISOString?.() || null,
    updatedAt: data.updatedAt?.toDate?.().toISOString?.() || null,
  };
}

async function handleQuote(req, res, decoded, admin, firestore) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }
  const quote = await calculateCryptoPknQuote({
    asset: req.body?.asset,
    amountIn: req.body?.amountIn,
  });
  const now = admin.firestore.FieldValue.serverTimestamp();
  const quoteRef = firestore.collection('crypto_pkn_purchase_quotes').doc();
  await quoteRef.set({
    ...quote,
    uid: decoded.uid,
    status: 'quoted',
    createdAt: now,
    updatedAt: now,
    quoteExpiresAtMs: Date.parse(quote.quoteExpiresAt),
  });
  return res.status(200).json(publicCryptoPknQuote(quoteRef.id, quote));
}

async function handleRequest(req, res, decoded, admin, firestore) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const quoteId = String(req.body?.quoteId || '').trim();
  const txHash = String(req.body?.depositTxHash || '').trim().toLowerCase();
  if (!quoteId) {
    return res.status(400).json({ error: 'Quote id is required.' });
  }
  if (!txHash) {
    return res.status(400).json({ error: 'Deposit transaction hash is required.' });
  }

  const quoteRef = firestore.collection('crypto_pkn_purchase_quotes').doc(quoteId);
  const requestRef = firestore.collection('crypto_pkn_purchase_requests').doc();
  const depositRef = firestore.collection('crypto_pkn_purchase_deposits').doc(txHash);
  const balanceRef = firestore.collection('balances').doc(decoded.uid);
  const userRef = firestore.collection('users').doc(decoded.uid);
  const ledgerRef = firestore.collection('ledger_entries').doc();

  let requestPayload = null;
  let verifiedDeposit = null;

  await firestore.runTransaction(async (transaction) => {
    const [quoteDoc, depositDoc, userDoc] = await Promise.all([
      transaction.get(quoteRef),
      transaction.get(depositRef),
      transaction.get(userRef),
    ]);
    if (!quoteDoc.exists) {
      throw Object.assign(new Error('Purchase quote was not found.'), { statusCode: 404 });
    }
    if (depositDoc.exists) {
      throw Object.assign(new Error('This deposit transaction was already used.'), {
        statusCode: 409,
      });
    }

    const quote = quoteDoc.data() || {};
    if (quote.uid !== decoded.uid) {
      throw Object.assign(new Error('This quote belongs to another user.'), { statusCode: 403 });
    }
    if (quote.status !== 'quoted') {
      throw Object.assign(new Error('This quote has already been used.'), { statusCode: 409 });
    }
    if (Date.now() > Number(quote.quoteExpiresAtMs || 0)) {
      transaction.update(quoteRef, {
        status: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw Object.assign(new Error('Quote expired. Request a new quote.'), {
        statusCode: 410,
      });
    }

    const asset = normalizeAsset(quote.fromAsset);
    const assetConfig = CHAIN_CONFIG[asset];
    const linkedWallet = assetConfig.bitcoin
      ? ''
      : normalizeAddress(
          userDoc.data()?.walletAddress,
          'Link the wallet that sent this crypto deposit before requesting PKN credit.',
        );
    verifiedDeposit = await verifyCryptoDeposit({
      asset,
      txHash,
      fromAddress: linkedWallet,
      expectedAmount: Number(quote.amountIn || 0),
    });

    const now = admin.firestore.FieldValue.serverTimestamp();
    requestPayload = {
      uid: decoded.uid,
      email: String(decoded.email || '').trim().toLowerCase(),
      quoteId,
      fromAsset: asset,
      toAsset: 'PKN',
      amountIn: Number(quote.amountIn || 0),
      amountOut: Number(quote.amountOut || 0),
      feeAmount: Number(quote.feeAmount || 0),
      marketPrice: Number(quote.marketPrice || 0),
      pknUsd: Number(quote.pknUsd || 0),
      chainId: Number(quote.chainId || 0),
      chainName: quote.chainName || '',
      depositTxHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      status: 'credited',
      createdAt: now,
      updatedAt: now,
    };

    transaction.set(requestRef, requestPayload);
    transaction.set(depositRef, {
      uid: decoded.uid,
      requestId: requestRef.id,
      txHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      fromAsset: asset,
      amountIn: verifiedDeposit.amountIn,
      amountOutPkn: requestPayload.amountOut,
      chainId: requestPayload.chainId,
      blockNumber: verifiedDeposit.blockNumber || null,
      createdAt: now,
    });
    transaction.set(
      balanceRef,
      {
        availablePkn: admin.firestore.FieldValue.increment(requestPayload.amountOut),
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(ledgerRef, {
      uid: decoded.uid,
      type: 'crypto_pkn_purchase_credit',
      amountPkn: requestPayload.amountOut,
      cryptoPknPurchaseRequestId: requestRef.id,
      depositTxHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      fromAsset: asset,
      amountIn: verifiedDeposit.amountIn,
      createdAt: now,
    });
    transaction.update(quoteRef, {
      status: 'credited',
      requestId: requestRef.id,
      depositTxHash: verifiedDeposit.txHash,
      updatedAt: now,
    });
  });

  return res.status(200).json({
    ok: true,
    requestId: requestRef.id,
    status: 'credited',
    amountPkn: requestPayload.amountOut,
    depositTxHash: verifiedDeposit.txHash,
  });
}

async function handleStatus(req, res, decoded, firestore) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }
  const requestId = String(req.query.requestId || '').trim();
  if (requestId) {
    const doc = await firestore.collection('crypto_pkn_purchase_requests').doc(requestId).get();
    if (!doc.exists || doc.data()?.uid !== decoded.uid) {
      return res.status(404).json({ error: 'Purchase request was not found.' });
    }
    return res.status(200).json({ request: serialize(doc) });
  }
  const snapshot = await firestore
    .collection('crypto_pkn_purchase_requests')
    .where('uid', '==', decoded.uid)
    .get();
  const requests = snapshot.docs
    .map(serialize)
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')))
    .slice(0, 12);
  return res.status(200).json({ requests });
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

    return res.status(404).json({ error: 'Purchase action was not found.' });
  } catch (error) {
    console.error('crypto-pkn-purchase failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Crypto PKN purchase failed.',
    });
  }
};
