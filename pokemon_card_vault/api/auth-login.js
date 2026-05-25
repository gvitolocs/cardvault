const { verifyBearerToken } = require('./_firebase');

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

function authPayload(decoded) {
  return {
    tokenType: 'Bearer',
    uid: decoded.uid,
    email: decoded.email || '',
    emailVerified: decoded.email_verified === true,
    expiresAt: decoded.exp ? new Date(decoded.exp * 1000).toISOString() : null,
    authTime: decoded.auth_time ? new Date(decoded.auth_time * 1000).toISOString() : null,
  };
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
    const decoded = await verifyBearerToken(req);
    return res.status(200).json({
      ok: true,
      auth: authPayload(decoded),
    });
  } catch (error) {
    console.error('auth-login failed', error);
    return res.status(error.statusCode || 401).json({
      error: error.message || 'Pokoin login failed.',
    });
  }
};

module.exports.authPayload = authPayload;
module.exports.setCorsHeaders = setCorsHeaders;
