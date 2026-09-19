const { getFirebaseAdmin } = require('../server/_firebase');
const { sendSignupNotificationOnce, sendWelcomeEmail } = require('../server/_email');
const { decryptPassword, hashValue } = require('../server/_pending_signup');
const { assignUniqueUsername, claimExactUsername } = require('../server/_username');

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
let sendSignupNotificationOverride = null;
let sendWelcomeOverride = null;

function getAdmin() {
  return adminOverride || getFirebaseAdmin();
}

function sendNotification(options) {
  return sendSignupNotificationOverride
    ? sendSignupNotificationOverride(options)
    : sendSignupNotificationOnce(options);
}

function sendWelcome(options) {
  return sendWelcomeOverride
    ? sendWelcomeOverride(options)
    : sendWelcomeEmail(options);
}

// Finalize a verified email signup into an ACTIVE Pokoin account exactly once.
// The pending-doc status gate is the idempotency point: only 'pending' can
// transition, and createUser is the atomicity point when two tabs race — the
// loser fails auth/email-already-exists without side effects. Any failure
// after user creation deletes the Firebase identity again so the verification
// link stays valid for a clean retry.
async function finalizeVerifiedUser({ admin, firestore, pending, pendingRef }) {
  const email = String(pending.email || '').trim().toLowerCase();
  const username = String(pending.username || '').trim().toLowerCase();
  const password = decryptPassword(pending.passwordPayload);

  try {
    await admin.auth().getUserByEmail(email);
    await pendingRef.set({ status: 'email_exists' }, { merge: true });
    throw Object.assign(new Error('Email is already registered.'), { statusCode: 409 });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      throw error;
    }
  }

  const userRecord = await admin.auth().createUser({
    email,
    password,
    ...(username ? { displayName: username } : {}),
    emailVerified: true,
  });

  try {
    await admin.auth().setCustomUserClaims(userRecord.uid, { pok_email_verified: true });

    const displayName = username;
    await firestore.collection('users').doc(userRecord.uid).set({
      uid: userRecord.uid,
      email,
      displayName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    let effectiveUsername = username;
    if (username) {
      try {
        await claimExactUsername({
          firestore,
          admin,
          uid: userRecord.uid,
          username,
          displayName: username,
          email,
        });
      } catch (error) {
        // The name was free at register time and got claimed meanwhile —
        // verification must still succeed, so fall back to a unique handle.
        if (error.statusCode !== 409) {
          throw error;
        }
        effectiveUsername = await assignUniqueUsername({
          firestore,
          admin,
          uid: userRecord.uid,
          base: username,
          displayName: username,
        });
      }
    } else {
      effectiveUsername = await assignUniqueUsername({
        firestore,
        admin,
        uid: userRecord.uid,
        base: email,
        displayName: '',
      });
    }

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

    const notificationDelivery = await sendNotification({
      admin,
      firestore,
      uid: userRecord.uid,
      provider: 'email_password',
      email,
      username: effectiveUsername,
      emailVerified: true,
    }).catch((error) => {
      console.error('signup notification failed', error);
      return { ok: false, error: error.message || 'Signup notification failed.' };
    });
    const welcomeDelivery = await sendWelcome({
      email,
      username: effectiveUsername,
    }).catch((error) => {
      console.error('welcome email failed', error);
      return { ok: false, error: error.message || 'Welcome email failed.' };
    });
    const customToken = await admin.auth().createCustomToken(userRecord.uid);
    const redirectPath = String(pending.redirectPath || '/');
    return {
      customToken,
      uid: userRecord.uid,
      username: effectiveUsername,
      redirectPath: redirectPath.startsWith('/') ? redirectPath : '/',
      signupNotification: notificationDelivery,
      welcomeEmail: welcomeDelivery,
    };
  } catch (error) {
    await admin.auth().deleteUser(userRecord.uid).catch(() => null);
    throw error;
  }
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
    const token = String(req.body?.token || '').trim();
    if (!token) {
      return res.status(400).json({ error: 'Verification token is missing.' });
    }

    const admin = getAdmin();
    const firestore = admin.firestore();
    const pendingRef = firestore.collection('pending_email_signups').doc(hashValue(token));
    const pendingDoc = await pendingRef.get();
    const pending = pendingDoc.data() || {};
    if (!pendingDoc.exists) {
      return res.status(400).json({
        error: 'This verification link is invalid or already used.',
        code: 'invalid_token',
      });
    }
    if (pending.status === 'completed') {
      return res.status(400).json({
        error: 'This email is already verified. Please sign in.',
        code: 'already_verified',
      });
    }
    if (pending.status !== 'pending') {
      return res.status(400).json({
        error: 'This verification link is invalid or already used.',
        code: 'invalid_token',
      });
    }
    const expiresAtMs = pending.expiresAt?.toMillis?.() || 0;
    if (!expiresAtMs || Date.now() > expiresAtMs) {
      await pendingRef.set({ status: 'expired' }, { merge: true });
      return res.status(400).json({
        error: 'This verification link has expired. Sign up again to get a fresh one.',
        code: 'expired_token',
      });
    }

    const result = await finalizeVerifiedUser({ admin, firestore, pending, pendingRef });
    return res.status(200).json(result);
  } catch (error) {
    console.error('verify-email-signup failed', error);
    if (error.code === 'auth/email-already-exists') {
      // A concurrent verification of the same pending signup created the
      // account first; nothing was duplicated here.
      return res.status(409).json({
        error: 'This email was just verified. Please sign in.',
        code: 'already_verified',
      });
    }
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Email verification failed.',
    });
  }
};

module.exports.setCorsHeaders = setCorsHeaders;
module.exports.finalizeVerifiedUser = finalizeVerifiedUser;
module.exports._test = {
  setAdminOverride(fn) {
    adminOverride = typeof fn === 'function' ? fn() : null;
  },
  setSendNotificationOverride(fn) {
    sendSignupNotificationOverride = fn || null;
  },
  setSendWelcomeOverride(fn) {
    sendWelcomeOverride = fn || null;
  },
};
