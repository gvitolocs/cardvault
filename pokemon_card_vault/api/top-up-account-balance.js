const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  addressTransactions,
  treasuryAddress,
  verifyNativeDeposit,
} = require('../server/_native_pkn');

function isWholePknAmount(amount) {
  return Number.isInteger(amount) && amount > 0;
}

const REGISTERED_ADDRESS = /^0x[a-f0-9]{40}$/;

async function registeredWalletAddresses(firestore, uid) {
  const snap = await firestore.collection('wallet_addresses').where('uid', '==', uid).limit(5).get();
  const addresses = [];
  snap.forEach((doc) => {
    const fromId = String(doc.id || '').trim().toLowerCase();
    const fromField = String(doc.data()?.address || '').trim().toLowerCase();
    for (const candidate of [fromId, fromField]) {
      if (REGISTERED_ADDRESS.test(candidate) && !addresses.includes(candidate)) {
        addresses.push(candidate);
      }
    }
  });
  return addresses;
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
    const addresses = await registeredWalletAddresses(firestore, decoded.uid);
    if (addresses.length === 0) {
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
            !addresses.includes(from) ||
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
            fromAddress: from,
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

    let verifiedFunding = null;
    let mismatch = null;
    for (const address of addresses) {
      try {
        verifiedFunding = await verifyNativeDeposit({
          txHash: fundingHash,
          fromAddress: address,
          expectedAmountPkn: amount,
        });
        break;
      } catch (error) {
        if (error.statusCode === 403) {
          mismatch = error;
          continue;
        }
        throw error;
      }
    }
    if (!verifiedFunding) {
      throw mismatch || Object.assign(new Error('Link a wallet before topping up your account balance.'), { statusCode: 400 });
    }

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
