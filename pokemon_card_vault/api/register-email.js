const { getFirebaseAdmin } = require('../server/_firebase');
const { sendVerificationEmail } = require('../server/_email');
const { encryptPassword, hashValue, newSignupToken } = require('../server/_pending_signup');
const { normalizeRequestedUsername } = require('../server/_username');

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PENDING_TTL_MS = 60 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const RESEND_MAX_SENDS = 10;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

function setCorsHeaders(res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
}

let adminOverride = null;
let sendVerificationOverride = null;

function getAdmin() {
  return adminOverride || getFirebaseAdmin();
}

function sendVerification(options) {
  return sendVerificationOverride
    ? sendVerificationOverride(options)
    : sendVerificationEmail(options);
}

function safeRedirectPath(value) {
  const raw = String(value || '').trim();
  return raw.startsWith('/') && !raw.startsWith('//') ? raw : '/';
}

async function startSignup(res, { email, password, username, redirectPath }) {
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters.' });
  }

  const admin = getAdmin();
  const firestore = admin.firestore();
  if (username) {
    const existingUsername = await firestore.collection('usernames').doc(username).get();
    if (existingUsername.exists) {
      return res.status(409).json({ error: 'Username is already taken.' });
    }
  }

  try {
    await admin.auth().getUserByEmail(email);
    return res.status(409).json({ error: 'Email is already registered.' });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      throw error;
    }
  }

  const token = newSignupToken();
  const tokenHash = hashValue(token);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + PENDING_TTL_MS);
  await firestore.collection('pending_email_signups').doc(tokenHash).set({
    email,
    username,
    passwordPayload: encryptPassword(password),
    redirectPath,
    status: 'pending',
    createdAt: now,
    expiresAt,
    sentCount: 1,
    lastSentAt: now,
  });
  await firestore.collection('pending_email_signups_by_email').doc(hashValue(email)).set({
    email,
    tokenHash,
    updatedAt: now,
  }, { merge: true });

  const siteUrl = process.env.PUBLIC_SITE_URL || 'https://pokoin.com';
  const verificationLink = `${siteUrl}/auth?signupToken=${encodeURIComponent(token)}`;
  const emailDelivery = await sendVerification({
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
}

async function resendVerification(res, { email }) {
  const admin = getAdmin();
  const firestore = admin.firestore();
  const pointer = (await firestore.collection('pending_email_signups_by_email').doc(hashValue(email)).get()).data() || {};
  const pendingDoc = pointer.tokenHash
    ? await firestore.collection('pending_email_signups').doc(pointer.tokenHash).get()
    : null;
  const pending = pendingDoc?.data() || {};
  if (!pendingDoc?.exists || pending.status !== 'pending') {
    return res.status(404).json({ error: 'No pending verification found for this email.' });
  }

  const lastSentMs = pending.lastSentAt?.toMillis?.() || 0;
  const cooldownRemainingMs = RESEND_COOLDOWN_MS - (Date.now() - lastSentMs);
  if (cooldownRemainingMs > 0) {
    return res.status(429).json({
      error: 'A verification email was just sent. Try again in a minute.',
      retryAfterSec: Math.ceil(cooldownRemainingMs / 1000),
    });
  }
  if (Number(pending.sentCount || 0) >= RESEND_MAX_SENDS) {
    return res.status(429).json({
      error: 'Too many verification emails requested. Sign up again later.',
    });
  }

  // The raw token only ever existed in the first email, so a resend mints a
  // fresh token/pending doc (reusing the encrypted credentials) and invalidates
  // the old link. One active token per email at any time.
  const now = admin.firestore.FieldValue.serverTimestamp();
  const token = newSignupToken();
  const tokenHash = hashValue(token);
  await firestore.collection('pending_email_signups').doc(tokenHash).set({
    email,
    username: String(pending.username || ''),
    passwordPayload: pending.passwordPayload,
    redirectPath: safeRedirectPath(pending.redirectPath),
    status: 'pending',
    createdAt: now,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + PENDING_TTL_MS),
    sentCount: Number(pending.sentCount || 0) + 1,
    lastSentAt: now,
  });
  await pendingDoc.ref.set({ status: 'superseded' }, { merge: true });
  await firestore.collection('pending_email_signups_by_email').doc(hashValue(email)).set({
    email,
    tokenHash,
    updatedAt: now,
  }, { merge: true });

  const siteUrl = process.env.PUBLIC_SITE_URL || 'https://pokoin.com';
  const verificationLink = `${siteUrl}/auth?signupToken=${encodeURIComponent(token)}`;
  const emailDelivery = await sendVerification({
    admin,
    email,
    username: String(pending.username || ''),
    verificationLink,
  });
  return res.status(200).json({
    ok: true,
    pending: true,
    resent: true,
    verificationEmail: emailDelivery,
  });
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    if (!EMAIL_RE.test(email)) {
      return res.status(400).json({ error: 'Enter a valid email address.' });
    }

    if (req.body?.resend) {
      return await resendVerification(res, { email });
    }

    const rawUsername = String(req.body?.username || '').trim();
    const username = rawUsername ? normalizeRequestedUsername(rawUsername) : '';
    return await startSignup(res, {
      email,
      password: String(req.body?.password || ''),
      username,
      redirectPath: safeRedirectPath(req.body?.redirectPath),
    });
  } catch (error) {
    console.error('register-email failed', error);
    const message = error.code === 'auth/email-already-exists'
      ? 'Email is already registered.'
      : error.message || 'Registration failed.';
    return res.status(error.statusCode || 500).json({ error: message });
  }
};

module.exports.setCorsHeaders = setCorsHeaders;
module.exports._test = {
  setAdminOverride(fn) {
    adminOverride = typeof fn === 'function' ? fn() : null;
  },
  setSendVerificationOverride(fn) {
    sendVerificationOverride = fn || null;
  },
};
