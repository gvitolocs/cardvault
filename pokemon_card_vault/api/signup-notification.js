const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { sendSignupNotificationOnce } = require('../server/_email');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const provider = String(req.body?.provider || 'unknown').trim();
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const userRecord = await admin.auth().getUser(decoded.uid);
    const userDoc = await firestore.collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};

    const delivery = await sendSignupNotificationOnce({
      admin,
      firestore,
      uid: decoded.uid,
      provider,
      email: userRecord.email || decoded.email || userData.email || '',
      username: userData.username || userRecord.displayName || '',
      walletAddress: userData.walletAddress || '',
      emailVerified: Boolean(userRecord.emailVerified || decoded.email_verified),
    });

    return res.status(200).json({ ok: true, signupNotification: delivery });
  } catch (error) {
    console.error('signup-notification failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Signup notification failed.',
    });
  }
};
