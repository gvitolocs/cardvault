const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { sendPknReceivedEmail } = require('../server/_email');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { recipientUsername, amountPkn } = req.body || {};
    const toUsername = String(recipientUsername || '').trim().toLowerCase();
    const amount = Number(amountPkn);

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
    const recipientUserRef = firestore.collection('users').doc(recipientUid);
    let senderUsername = '';
    let recipientEmail = '';
    let recipientDisplayUsername = toUsername;

    await firestore.runTransaction(async (transaction) => {
      const senderBalance = await transaction.get(senderBalanceRef);
      const senderUser = await transaction.get(senderUserRef);
      const recipientUser = await transaction.get(recipientUserRef);
      const available = Number(senderBalance.data()?.availablePkn || 0);
      if (available < amount) {
        throw Object.assign(new Error('Your account balance is too low.'), { statusCode: 400 });
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      senderUsername = String(senderUser.data()?.username || '').trim().toLowerCase();
      recipientEmail = String(recipientUser.data()?.email || '').trim().toLowerCase();
      recipientDisplayUsername = String(recipientUser.data()?.username || toUsername).trim().toLowerCase();
      transaction.set(
        senderBalanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(-amount),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(
        recipientBalanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(amount),
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
        type: 'account_transfer_received',
        amountPkn: amount,
        counterpartyUid: decoded.uid,
        counterpartyUsername: senderUsername,
        createdAt: now,
      });
    });

    const emailDelivery = await sendPknReceivedEmail({
      email: recipientEmail,
      username: recipientDisplayUsername,
      amountPkn: amount,
      senderUsername,
    }).catch((error) => {
      console.error('pkn received email failed', error);
      return { ok: false, error: error.message || 'PKN received email failed.' };
    });

    return res.status(200).json({
      ok: true,
      creditedAccountBalance: true,
      emailNotification: emailDelivery,
    });
  } catch (error) {
    console.error('transfer-account-balance failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Account transfer failed.',
    });
  }
};
