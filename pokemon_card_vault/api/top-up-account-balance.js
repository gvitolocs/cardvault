const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { verifyNativeDeposit } = require('../server/_native_pkn');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { amountPkn, fundingTxHash } = req.body || {};
    const amount = Number(amountPkn);
    const fundingHash = String(fundingTxHash || '').trim().toLowerCase();

    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: 'Enter a whole PKN amount greater than zero.' });
    }
    if (!fundingHash) {
      return res.status(400).json({ error: 'Missing top-up transaction hash.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const userRef = firestore.collection('users').doc(decoded.uid);
    const balanceRef = firestore.collection('balances').doc(decoded.uid);
    const fundingRef = firestore.collection('native_pkn_deposits').doc(fundingHash);
    const userDoc = await userRef.get();
    const walletAddress = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
    if (!walletAddress) {
      return res.status(400).json({ error: 'Link a wallet before topping up your account balance.' });
    }
    const verifiedFunding = await verifyNativeDeposit({
      txHash: fundingHash,
      fromAddress: walletAddress,
      expectedAmountPkn: amount,
    });

    await firestore.runTransaction(async (transaction) => {
      const fundingDoc = await transaction.get(fundingRef);
      if (fundingDoc.exists) {
        throw Object.assign(new Error('This top-up transaction was already used.'), {
          statusCode: 409,
        });
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.set(fundingRef, {
        uid: decoded.uid,
        txHash: fundingHash,
        fromAddress: verifiedFunding.fromAddress,
        amountPkn: verifiedFunding.amountPkn,
        purpose: 'account_top_up',
        createdAt: now,
      });
      transaction.set(
        balanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(verifiedFunding.amountPkn),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(firestore.collection('ledger_entries').doc(), {
        uid: decoded.uid,
        type: 'account_top_up',
        amountPkn: verifiedFunding.amountPkn,
        txHash: fundingHash,
        fromAddress: verifiedFunding.fromAddress,
        createdAt: now,
      });
    });

    return res.status(200).json({
      ok: true,
      amountPkn: verifiedFunding.amountPkn,
      txHash: fundingHash,
    });
  } catch (error) {
    console.error('top-up-account-balance failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Account top-up failed.',
    });
  }
};
