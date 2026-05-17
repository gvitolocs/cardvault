const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { sendNativePkn, verifyNativeDeposit } = require('../server/_native_pkn');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { recipientUsername, amountPkn, fundingTxHash } = req.body || {};
    const toUsername = String(recipientUsername || '').trim().toLowerCase();
    const amount = Number(amountPkn);
    const fundingHash = String(fundingTxHash || '').trim().toLowerCase();

    if (!/^[a-z0-9]{3,32}$/.test(toUsername)) {
      return res.status(400).json({ error: 'Enter a valid recipient username.' });
    }
    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: 'Enter a whole PKN amount greater than zero.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const usernameDoc = await firestore.collection('usernames').doc(toUsername).get();

    if (!usernameDoc.exists || !usernameDoc.data()?.uid) {
      return res.status(404).json({ error: 'No Pokoin account was found for that username.' });
    }

    const recipientUid = usernameDoc.data().uid;
    if (recipientUid === decoded.uid) {
      return res.status(400).json({ error: 'You cannot send PKN to your own account.' });
    }
    const senderBalanceRef = firestore.collection('balances').doc(decoded.uid);
    const recipientBalanceRef = firestore.collection('balances').doc(recipientUid);
    const senderUserRef = firestore.collection('users').doc(decoded.uid);
    const senderWalletRef = firestore.collection('users').doc(decoded.uid);
    const recipientUserRef = firestore.collection('users').doc(recipientUid);
    const fundingRef = fundingHash
      ? firestore.collection('native_pkn_deposits').doc(fundingHash)
      : null;
    let verifiedFunding = null;
    if (fundingHash) {
      const senderProfile = await senderWalletRef.get();
      verifiedFunding = await verifyNativeDeposit({
        txHash: fundingHash,
        fromAddress: senderProfile.data()?.walletAddress,
        expectedAmountPkn: amount,
      });
    }
    let recipientLinkedWallet = '';
    let payoutTxHash = null;

    await firestore.runTransaction(async (transaction) => {
      const senderBalance = await transaction.get(senderBalanceRef);
      const senderUser = await transaction.get(senderUserRef);
      const recipientUser = await transaction.get(recipientUserRef);
      const available = Number(senderBalance.data()?.availablePkn || 0);
      const totalAvailable = available + (verifiedFunding?.amountPkn || 0);
      if (totalAvailable < amount) {
        throw Object.assign(new Error('Your account balance is too low.'), { statusCode: 400 });
      }
      if (fundingRef) {
        const fundingDoc = await transaction.get(fundingRef);
        if (fundingDoc.exists) {
          throw Object.assign(new Error('This funding transaction was already used.'), {
            statusCode: 409,
          });
        }
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      const senderUsername = String(senderUser.data()?.username || '').trim().toLowerCase();
      recipientLinkedWallet = String(recipientUser.data()?.walletAddress || '').trim().toLowerCase();
      if (fundingRef) {
        transaction.set(fundingRef, {
          uid: decoded.uid,
          txHash: fundingHash,
          fromAddress: verifiedFunding.fromAddress,
          amountPkn: verifiedFunding.amountPkn,
          createdAt: now,
        });
        transaction.set(firestore.collection('ledger_entries').doc(), {
          uid: decoded.uid,
          type: 'wallet_funding_received',
          amountPkn: verifiedFunding.amountPkn,
          txHash: fundingHash,
          fromAddress: verifiedFunding.fromAddress,
          createdAt: now,
        });
      }
      transaction.set(
        senderBalanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(
            (verifiedFunding?.amountPkn || 0) - amount,
          ),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(
        recipientBalanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(recipientLinkedWallet ? 0 : amount),
          lockedPkn: admin.firestore.FieldValue.increment(recipientLinkedWallet ? amount : 0),
          updatedAt: now,
        },
        { merge: true },
      );
      const ledger = firestore.collection('ledger_entries');
      transaction.set(ledger.doc(), {
        uid: decoded.uid,
        type: 'account_transfer_sent',
        amountPkn: -amount,
        counterpartyUid: recipientUid,
        counterpartyUsername: toUsername,
        createdAt: now,
      });
      transaction.set(ledger.doc(), {
        uid: recipientUid,
        type: recipientLinkedWallet ? 'account_transfer_payout_pending' : 'account_transfer_received',
        amountPkn: amount,
        counterpartyUid: decoded.uid,
        counterpartyUsername: senderUsername,
        toAddress: recipientLinkedWallet || null,
        createdAt: now,
      });
    });

    if (recipientLinkedWallet) {
      const payout = await sendNativePkn({ toAddress: recipientLinkedWallet, amountPkn: amount });
      payoutTxHash = payout.txHash;
      if (payoutTxHash) {
        await firestore.runTransaction(async (transaction) => {
          const now = admin.firestore.FieldValue.serverTimestamp();
          transaction.set(
            recipientBalanceRef,
            {
              lockedPkn: admin.firestore.FieldValue.increment(-amount),
              updatedAt: now,
            },
            { merge: true },
          );
          transaction.set(firestore.collection('ledger_entries').doc(), {
            uid: recipientUid,
            type: 'account_transfer_payout_sent',
            amountPkn: amount,
            fromUid: decoded.uid,
            toAddress: recipientLinkedWallet,
            payoutTxHash,
            createdAt: now,
          });
        });
      }
    }

    return res.status(200).json({
      ok: true,
      fundedFromWallet: Boolean(verifiedFunding),
      recipientWalletAddress: recipientLinkedWallet || null,
      payoutTxHash,
    });
  } catch (error) {
    console.error('transfer-account-balance failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Account transfer failed.',
    });
  }
};
