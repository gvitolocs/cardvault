const { getFirebaseAdmin } = require('../server/_firebase');
const { sendVerificationEmail } = require('../server/_email');
const { encryptPassword, hashValue, newSignupToken } = require('../server/_pending_signup');
const { normalizeRequestedUsername } = require('../server/_username');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    const password = String(req.body?.password || '');
    const username = normalizeRequestedUsername(req.body?.username);

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return res.status(400).json({ error: 'Enter a valid email address.' });
    }
    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const existingUsername = await firestore.collection('usernames').doc(username).get();
    if (existingUsername.exists) {
      return res.status(409).json({ error: 'Username is already taken.' });
    }

    try {
      await admin.auth().getUserByEmail(email);
      return res.status(409).json({ error: 'Email is already registered.' });
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw error;
      }
    }

    const redirectPath = String(req.body?.redirectPath || '/').trim();
    const safeRedirectPath = redirectPath.startsWith('/') && !redirectPath.startsWith('//')
      ? redirectPath
      : '/';
    const token = newSignupToken();
    const tokenHash = hashValue(token);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 60 * 60 * 1000);
    const pendingRef = firestore.collection('pending_email_signups').doc(tokenHash);
    await pendingRef.set({
      email,
      username,
      passwordPayload: encryptPassword(password),
      redirectPath: safeRedirectPath,
      status: 'pending',
      createdAt: now,
      expiresAt,
    });

    const siteUrl = process.env.PUBLIC_SITE_URL || 'https://pokoin.com';
    const verificationLink = `${siteUrl}/auth?signupToken=${encodeURIComponent(token)}`;
    const emailDelivery = await sendVerificationEmail({
      admin,
      email,
      username,
      verificationLink,
    });
    return res.status(200).json({
      ok: true,
      pending: true,
      username,
      verificationEmail: emailDelivery,
    });
  } catch (error) {
    console.error('register-email failed', error);
    const message = error.code === 'auth/email-already-exists'
      ? 'Email is already registered.'
      : error.message || 'Registration failed.';
    return res.status(error.statusCode || 500).json({ error: message });
  }
};
