const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  addressTransactions,
  treasuryAddress,
  verifyNativeDeposit,
} = require('../server/_native_pkn');

function isWholePknAmount(amount) {
  return Number.isInteger(amount) && amount > 0;
}

async function creditVerifiedTopUp({
  admin,
  firestore,
  uid,
  fundingHash,
  verifiedFunding,
  reconciled = false,
}) {
  const balanceRef = firestore.collection('balances').doc(uid);
  const fundingRef = firestore.collection('native_pkn_deposits').doc(fundingHash);
  let credited = false;

  await firestore.runTransaction(async (transaction) => {
    const fundingDoc = await transaction.get(fundingRef);
    if (fundingDoc.exists) {
      const data = fundingDoc.data() || {};
      if (data.uid === uid) {
        return;
      }
      throw Object.assign(new Error('This top-up transaction was already used by another account.'), {
        statusCode: 409,
      });
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(fundingRef, {
      uid,
      txHash: fundingHash,
      fromAddress: verifiedFunding.fromAddress,
      amountPkn: verifiedFunding.amountPkn,
      purpose: 'account_top_up',
      ...(reconciled ? { reconciled: true } : {}),
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
      uid,
      type: 'account_top_up',
      amountPkn: verifiedFunding.amountPkn,
      txHash: fundingHash,
      fromAddress: verifiedFunding.fromAddress,
      ...(reconciled ? { reconciled: true } : {}),
      createdAt: now,
    });
    credited = true;
  });

  return credited;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { amountPkn, fundingTxHash, reconcileRecent } = req.body || {};
    const amount = Number(amountPkn);
    const fundingHash = String(fundingTxHash || '').trim().toLowerCase();

    if (!reconcileRecent && !isWholePknAmount(amount)) {
      return res.status(400).json({ error: 'Enter a whole PKN amount greater than zero.' });
    }
    if (!reconcileRecent && !fundingHash) {
      return res.status(400).json({ error: 'Missing top-up transaction hash.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const userRef = firestore.collection('users').doc(decoded.uid);
    const userDoc = await userRef.get();
    const walletAddress = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
    if (!walletAddress) {
      return res.status(400).json({ error: 'Link a wallet before topping up your account balance.' });
    }

    if (reconcileRecent) {
      if (!isWholePknAmount(amount)) {
        return res.status(400).json({ error: 'Enter the whole PKN amount to reconcile.' });
      }
      const bank = treasuryAddress();
      const transactions = await addressTransactions(bank, { limit: 40 });
      let creditedCount = 0;
      let creditedAmountPkn = 0;
      const creditedTxHashes = [];

      for (const tx of transactions) {
        const txHash = String(tx.hash || '').trim().toLowerCase();
        const from = String(tx.from || '').trim().toLowerCase();
        const to = String(tx.to || '').trim().toLowerCase();
        const txAmount = Number(tx.amount ?? tx.value ?? 0);
        if (!/^0x[a-f0-9]{64}$/.test(txHash) ||
            from !== walletAddress ||
            to !== bank ||
            txAmount !== amount) {
          continue;
        }
        const credited = await creditVerifiedTopUp({
          admin,
          firestore,
          uid: decoded.uid,
          fundingHash: txHash,
          verifiedFunding: {
            txHash,
            fromAddress: walletAddress,
            amountPkn: txAmount,
          },
          reconciled: true,
        });
        if (credited) {
          creditedCount += 1;
          creditedAmountPkn += txAmount;
          creditedTxHashes.push(txHash);
        }
      }

      return res.status(200).json({
        ok: true,
        creditedCount,
        creditedAmountPkn,
        creditedTxHashes,
      });
    }

    const verifiedFunding = await verifyNativeDeposit({
      txHash: fundingHash,
      fromAddress: walletAddress,
      expectedAmountPkn: amount,
    });

    const credited = await creditVerifiedTopUp({
      admin,
      firestore,
      uid: decoded.uid,
      fundingHash,
      verifiedFunding,
    });

    return res.status(200).json({
      ok: true,
      amountPkn: verifiedFunding.amountPkn,
      txHash: fundingHash,
      credited,
    });
  } catch (error) {
    console.error('top-up-account-balance failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Account top-up failed.',
    });
  }
};
