const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { usernameForRequest } = require('../server/_username');

// POST {} → the caller's registered username (repaired or assigned).
// POST {username} → claim that exact name (409 when another account has it).
// The Flutter profile screen calls this path; the web uses the same logic
// through POST /api/search-recipient-emails.
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const username = await usernameForRequest({
      firestore: admin.firestore(),
      admin,
      decoded,
      requestedUsername: req.body?.username,
    });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json({ username });
  } catch (error) {
    console.error('ensure-username failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Username update failed.',
    });
  }
};
