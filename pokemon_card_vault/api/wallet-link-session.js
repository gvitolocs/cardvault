const crypto = require('crypto');
const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');

const sessionTtlMs = 10 * 60 * 1000;

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const sessionId = crypto.randomBytes(24).toString('hex');
    const nowMs = Date.now();
    const returnPath = String(req.body?.returnPath || '/profile').trim();

    await admin.firestore().collection('wallet_link_sessions').doc(sessionId).set({
      uid: decoded.uid,
      email: String(decoded.email || '').trim().toLowerCase(),
      returnPath: returnPath.startsWith('/') && !returnPath.startsWith('//') ? returnPath : '/profile',
      used: false,
      createdAtMs: nowMs,
      expiresAtMs: nowMs + sessionTtlMs,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).json({
      sessionId,
      expiresAt: new Date(nowMs + sessionTtlMs).toISOString(),
    });
  } catch (error) {
    console.error('wallet-link-session failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Wallet link session failed.',
    });
  }
};
