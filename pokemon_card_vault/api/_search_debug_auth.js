const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');

const ALLOWED_IDENTIFIERS = new Set([
  'vitologiuseppe17',
  'vitologiuseppe17@gmail.com',
  'pokoinpos@gmail.com',
]);

function normalize(value) {
  return String(value || '').trim().toLowerCase();
}

function configuredIdentifiers() {
  return [
    process.env.MARKETPLACE_ADMIN_EMAILS || '',
    process.env.MARKETPLACE_DEBUG_EMAILS || '',
    process.env.ADMIN_SIGNUP_EMAIL || '',
  ]
    .join(',')
    .split(',')
    .map(normalize)
    .filter(Boolean);
}

function hasAdminAccess(profile) {
  const role = normalize(profile?.role);
  return profile?.admin === true ||
    profile?.isAdmin === true ||
    profile?.hasAdminAccess === true ||
    role === 'admin';
}

async function authorizeSearchDebugRequest(req) {
  const decoded = await verifyBearerToken(req);
  const email = normalize(decoded.email);
  const uid = decoded.uid;
  let username = normalize(decoded.username || decoded.name);
  const envIdentifiers = new Set(configuredIdentifiers());
  if (
    ALLOWED_IDENTIFIERS.has(username) ||
    ALLOWED_IDENTIFIERS.has(email) ||
    envIdentifiers.has(email) ||
    hasAdminAccess(decoded)
  ) {
    return { uid, email, username };
  }
  try {
    const snapshot = await getFirebaseAdmin()
      .firestore()
      .collection('users')
      .doc(uid)
      .get();
    const data = snapshot.data() || {};
    username = normalize(data.username) || username;
    if (
      ALLOWED_IDENTIFIERS.has(username) ||
      ALLOWED_IDENTIFIERS.has(email) ||
      envIdentifiers.has(email) ||
      hasAdminAccess(data)
    ) {
      return { uid, email, username };
    }
  } catch (error) {
    console.warn('search debug profile lookup failed', error);
  }
  const error = new Error('Search debug is not enabled for this account.');
  error.statusCode = 403;
  throw error;
}

module.exports = {
  authorizeSearchDebugRequest,
  _test: {
    configuredIdentifiers,
    hasAdminAccess,
  },
};
