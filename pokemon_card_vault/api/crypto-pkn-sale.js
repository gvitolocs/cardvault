const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { verifyNativeDeposit } = require('../server/_native_pkn');
const {
  calculatePknCryptoSaleQuote,
  assertPayoutLiquidity,
  normalizeAsset,
  normalizePayoutAddress,
  publicPknCryptoSaleQuote,
  sendCryptoPayout,
} = require('../server/_crypto_pkn_purchase');

function boolEnv(name, fallback = false) {
  const value = String(process.env[name] || '').trim().toLowerCase();
  if (!value) {
    return fallback;
  }
  return ['1', 'true', 'yes', 'on'].includes(value);
}

function serialize(doc) {
  const data = doc.data() || {};
  return {
    requestId: doc.id,
    quoteId: data.quoteId || '',
    fromAsset: data.fromAsset || 'PKN',
    toAsset: data.toAsset || '',
    amountIn: Number(data.amountIn || 0),
    amountOut: Number(data.amountOut || 0),
    feeAmount: Number(data.feeAmount || 0),
    depositTxHash: data.depositTxHash || null,
    fromAddress: data.fromAddress || '',
    payoutAddress: data.payoutAddress || '',
    payoutTxHash: data.payoutTxHash || null,
    status: data.status || 'pending_liquidity',
    settlementMode: data.settlementMode || 'manual_settlement',
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
  if (!boolEnv('CRYPTO_PKN_SELL_ENABLED', true)) {
    return res.status(403).json({ error: 'PKN to crypto sales are not enabled yet.' });
  }

  const quote = await calculatePknCryptoSaleQuote({
    asset: req.body?.asset,
    amountIn: req.body?.amountIn,
  });
  const liquidity = await assertPayoutLiquidity({
    asset: quote.toAsset,
    amountOut: quote.amountOut,
  });
  const now = admin.firestore.FieldValue.serverTimestamp();
  const quoteRef = firestore.collection('crypto_pkn_sale_quotes').doc();
  await quoteRef.set({
    ...quote,
    uid: decoded.uid,
    status: 'quoted',
    createdAt: now,
    updatedAt: now,
    quoteExpiresAtMs: Date.parse(quote.quoteExpiresAt),
    payoutLiquidityAvailable: liquidity.available,
  });
  return res.status(200).json({
    ...publicPknCryptoSaleQuote(quoteRef.id, quote),
    payoutLiquidityAvailable: liquidity.available,
  });
}

async function handleRequest(req, res, decoded, admin, firestore) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }
  if (!boolEnv('CRYPTO_PKN_SELL_ENABLED', true)) {
    return res.status(403).json({ error: 'PKN to crypto sales are not enabled yet.' });
  }

  const quoteId = String(req.body?.quoteId || '').trim();
  if (!quoteId) {
    return res.status(400).json({ error: 'Quote id is required.' });
  }

  const quoteRef = firestore.collection('crypto_pkn_sale_quotes').doc(quoteId);
  const requestRef = firestore.collection('crypto_pkn_sale_requests').doc();
  const depositTxHash = String(req.body?.depositTxHash || '').trim().toLowerCase();
  const depositRef = firestore.collection('native_pkn_deposits').doc(depositTxHash);
  const payoutRef = firestore.collection('crypto_pkn_sale_payouts').doc(requestRef.id);
  const userRef = firestore.collection('users').doc(decoded.uid);
  const ledgerRef = firestore.collection('ledger_entries').doc();

  let requestPayload = null;
  let verifiedDeposit = null;

  if (!depositTxHash) {
    return res.status(400).json({ error: 'Missing PKN funding transaction hash.' });
  }

  await firestore.runTransaction(async (transaction) => {
    const [quoteDoc, depositDoc, userDoc] = await Promise.all([
      transaction.get(quoteRef),
      transaction.get(depositRef),
      transaction.get(userRef),
    ]);
    if (!quoteDoc.exists) {
      throw Object.assign(new Error('Sale quote was not found.'), { statusCode: 404 });
    }
    if (depositDoc.exists) {
      throw Object.assign(new Error('This PKN funding transaction was already used.'), {
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

    const asset = normalizeAsset(quote.toAsset);
    const payoutAddress = normalizePayoutAddress(asset, req.body?.payoutAddress);
    const amountPkn = Number(quote.amountIn || 0);
    const walletAddress = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
    if (!walletAddress) {
      throw Object.assign(
        new Error('Link the wallet that sends this PKN before requesting crypto payout.'),
        { statusCode: 400 },
      );
    }
    verifiedDeposit = await verifyNativeDeposit({
      txHash: depositTxHash,
      fromAddress: walletAddress,
      expectedAmountPkn: amountPkn,
    });

    const autoPayoutEnabled = boolEnv('CRYPTO_PKN_AUTO_PAYOUT_ENABLED', true);
    const now = admin.firestore.FieldValue.serverTimestamp();
    requestPayload = {
      uid: decoded.uid,
      email: String(decoded.email || '').trim().toLowerCase(),
      quoteId,
      fromAsset: 'PKN',
      toAsset: asset,
      amountIn: amountPkn,
      amountOut: Number(quote.amountOut || 0),
      feeAmount: Number(quote.feeAmount || 0),
      feeBps: Number(quote.feeBps || 0),
      marketPrice: Number(quote.marketPrice || 0),
      pknUsd: Number(quote.pknUsd || 0),
      chainId: Number(quote.chainId || 0),
      chainName: quote.chainName || '',
      depositTxHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      payoutAddress,
      payoutTxHash: null,
      status: autoPayoutEnabled ? 'payout_pending' : 'pending_liquidity',
      settlementMode: autoPayoutEnabled ? 'automatic_pending' : 'manual_settlement',
      createdAt: now,
      updatedAt: now,
    };

    transaction.set(depositRef, {
      uid: decoded.uid,
      requestId: requestRef.id,
      txHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      amountPkn: verifiedDeposit.amountPkn,
      purpose: 'crypto_pkn_sale',
      createdAt: now,
    });
    transaction.set(requestRef, requestPayload);
    transaction.set(payoutRef, {
      uid: decoded.uid,
      requestId: requestRef.id,
      toAsset: asset,
      amountOut: requestPayload.amountOut,
      payoutAddress,
      status: requestPayload.status,
      payoutTxHash: null,
      createdAt: now,
      updatedAt: now,
    });
    transaction.set(ledgerRef, {
      uid: decoded.uid,
      type: 'crypto_pkn_sale_pkn_deposited',
      amountPkn: -verifiedDeposit.amountPkn,
      cryptoPknSaleRequestId: requestRef.id,
      depositTxHash: verifiedDeposit.txHash,
      fromAddress: verifiedDeposit.fromAddress,
      toAsset: asset,
      amountOut: requestPayload.amountOut,
      payoutAddress,
      status: requestPayload.status,
      createdAt: now,
    });
    transaction.update(quoteRef, {
      status: requestPayload.status,
      requestId: requestRef.id,
      payoutAddress,
      updatedAt: now,
    });
  });

  let payout = { mode: requestPayload.settlementMode, txHash: null };
  if (boolEnv('CRYPTO_PKN_AUTO_PAYOUT_ENABLED', true)) {
    try {
      payout = await sendCryptoPayout({
        asset: requestPayload.toAsset,
        toAddress: requestPayload.payoutAddress,
        amountOut: requestPayload.amountOut,
      });
    } catch (payoutError) {
      payout = {
        mode: 'payout_failed',
        txHash: null,
        error: payoutError.message || 'Automatic crypto payout failed.',
      };
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (payout.txHash) {
      await firestore.runTransaction(async (transaction) => {
        transaction.set(
          requestRef,
          {
            status: 'payout_submitted',
            settlementMode: payout.mode,
            payoutTxHash: payout.txHash,
            payoutFromAddress: payout.fromAddress || null,
            updatedAt: now,
          },
          { merge: true },
        );
        transaction.set(
          payoutRef,
          {
            status: 'payout_submitted',
            settlementMode: payout.mode,
            payoutTxHash: payout.txHash,
            payoutFromAddress: payout.fromAddress || null,
            updatedAt: now,
          },
          { merge: true },
        );
        transaction.set(firestore.collection('ledger_entries').doc(), {
          uid: decoded.uid,
          type: 'crypto_pkn_sale_crypto_payout_submitted',
          amountPkn: 0,
          cryptoPknSaleRequestId: requestRef.id,
          toAsset: requestPayload.toAsset,
          amountOut: requestPayload.amountOut,
          payoutAddress: requestPayload.payoutAddress,
          payoutTxHash: payout.txHash,
          createdAt: now,
        });
      });
      requestPayload.status = 'payout_submitted';
      requestPayload.settlementMode = payout.mode;
      requestPayload.payoutTxHash = payout.txHash;
    } else {
      await firestore.runTransaction(async (transaction) => {
        transaction.set(
          requestRef,
          {
            status: payout.mode === 'bitcoin_manual_pending' ? 'manual_settlement' : 'pending_liquidity',
            settlementMode: payout.mode,
            payoutWarning: payout.warning || payout.error || null,
            updatedAt: now,
          },
          { merge: true },
        );
        transaction.set(
          payoutRef,
          {
            status: payout.mode === 'bitcoin_manual_pending' ? 'manual_settlement' : 'pending_liquidity',
            settlementMode: payout.mode,
            payoutWarning: payout.warning || payout.error || null,
            updatedAt: now,
          },
          { merge: true },
        );
      });
      requestPayload.status =
        payout.mode === 'bitcoin_manual_pending' ? 'manual_settlement' : 'pending_liquidity';
      requestPayload.settlementMode = payout.mode;
    }
  }

  return res.status(200).json({
    ok: true,
    requestId: requestRef.id,
    status: requestPayload.status,
    settlementMode: requestPayload.settlementMode,
    amountPknDeposited: verifiedDeposit.amountPkn,
    amountOut: requestPayload.amountOut,
    toAsset: requestPayload.toAsset,
    depositTxHash: verifiedDeposit.txHash,
    payoutAddress: requestPayload.payoutAddress,
    payoutTxHash: requestPayload.payoutTxHash || null,
    message:
      requestPayload.payoutTxHash
        ? 'PKN received. Crypto payout was submitted.'
        : 'PKN received. Crypto payout is pending settlement.',
  });
}

async function handleStatus(req, res, decoded, firestore) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }
  const requestId = String(req.query.requestId || '').trim();
  if (requestId) {
    const doc = await firestore.collection('crypto_pkn_sale_requests').doc(requestId).get();
    if (!doc.exists || doc.data()?.uid !== decoded.uid) {
      return res.status(404).json({ error: 'Sale request was not found.' });
    }
    return res.status(200).json({ request: serialize(doc) });
  }
  const snapshot = await firestore
    .collection('crypto_pkn_sale_requests')
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

    return res.status(404).json({ error: 'Sale action was not found.' });
  } catch (error) {
    console.error('crypto-pkn-sale failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Crypto PKN sale failed.',
    });
  }
};
