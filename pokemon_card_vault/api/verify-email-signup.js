const { getFirebaseAdmin } = require('../server/_firebase');
const { sendSignupNotificationOnce, sendWelcomeEmail } = require('../server/_email');
const { decryptPassword, hashValue } = require('../server/_pending_signup');
const { claimExactUsername } = require('../server/_username');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  let userRecord;
  try {
    const token = String(req.body?.token || '').trim();
    if (!token) {
      return res.status(400).json({ error: 'Verification token is missing.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const pendingRef = firestore.collection('pending_email_signups').doc(hashValue(token));
    const pendingDoc = await pendingRef.get();
    const pending = pendingDoc.data() || {};
    if (!pendingDoc.exists || pending.status !== 'pending') {
      return res.status(400).json({ error: 'This verification link is invalid or already used.' });
    }
    const expiresAtMs = pending.expiresAt?.toMillis?.() || 0;
    if (!expiresAtMs || Date.now() > expiresAtMs) {
      await pendingRef.set({ status: 'expired' }, { merge: true });
      return res.status(400).json({ error: 'This verification link has expired.' });
    }

    const email = String(pending.email || '').trim().toLowerCase();
    const username = String(pending.username || '').trim().toLowerCase();
    const password = decryptPassword(pending.passwordPayload);
    try {
      await admin.auth().getUserByEmail(email);
      await pendingRef.set({ status: 'email_exists' }, { merge: true });
      return res.status(409).json({ error: 'Email is already registered.' });
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw error;
      }
    }

    userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: username,
      emailVerified: true,
    });
    await claimExactUsername({
      firestore,
      admin,
      uid: userRecord.uid,
      username,
      displayName: username,
      email,
    });
    await firestore.collection('balances').doc(userRecord.uid).set(
      {
        availablePkn: admin.firestore.FieldValue.increment(0),
        lockedPkn: admin.firestore.FieldValue.increment(0),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await pendingRef.set({
      status: 'completed',
      uid: userRecord.uid,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const notificationDelivery = await sendSignupNotificationOnce({
      admin,
      firestore,
      uid: userRecord.uid,
      provider: 'email_password',
      email,
      username,
      emailVerified: true,
    });
    const welcomeDelivery = await sendWelcomeEmail({
      email,
      username,
    }).catch((error) => {
      console.error('welcome email failed', error);
      return { ok: false, error: error.message || 'Welcome email failed.' };
    });
    const customToken = await admin.auth().createCustomToken(userRecord.uid);
    const redirectPath = String(pending.redirectPath || '/');
    return res.status(200).json({
      customToken,
      uid: userRecord.uid,
      username,
      redirectPath: redirectPath.startsWith('/') ? redirectPath : '/',
      signupNotification: notificationDelivery,
      welcomeEmail: welcomeDelivery,
    });
  } catch (error) {
    if (userRecord?.uid) {
      await getFirebaseAdmin().auth().deleteUser(userRecord.uid).catch(() => null);
    }
    console.error('verify-email-signup failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Email verification failed.',
    });
  }
};
