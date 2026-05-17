const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { toAddress, amountPkn } = req.body || {};
    const address = String(toAddress || '').trim();
    const amount = Number(amountPkn);

    if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
      return res.status(400).json({ error: 'Enter a valid 0x payout address.' });
    }
    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: 'Enter a whole PKN amount greater than zero.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const balanceRef = firestore.collection('balances').doc(decoded.uid);
    const requestRef = firestore.collection('withdraw_requests').doc();
    const ledgerRef = firestore.collection('ledger_entries').doc();

    await firestore.runTransaction(async (transaction) => {
      const balanceDoc = await transaction.get(balanceRef);
      const available = Number(balanceDoc.data()?.availablePkn || 0);
      if (available < amount) {
        throw Object.assign(new Error('Your site balance is too low.'), { statusCode: 400 });
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.set(
        balanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(-amount),
          lockedPkn: admin.firestore.FieldValue.increment(amount),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(requestRef, {
        uid: decoded.uid,
        email: String(decoded.email || '').trim().toLowerCase(),
        toAddress: address,
        amountPkn: amount,
        status: 'pending',
        source: 'site_balance',
        createdAt: now,
        updatedAt: now,
      });
      transaction.set(ledgerRef, {
        uid: decoded.uid,
        type: 'withdraw_requested',
        amountPkn: -amount,
        toAddress: address,
        withdrawRequestId: requestRef.id,
        createdAt: now,
      });
    });

    return res.status(200).json({ ok: true, requestId: requestRef.id });
  } catch (error) {
    console.error('request-pkn-withdraw failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Withdraw request failed.',
    });
  }
};
