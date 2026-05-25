const { getFirebaseAdmin } = require('./_firebase');

function normalize(value) {
  return String(value || '').trim().toLowerCase();
}

function roleEntries(value) {
  if (!value) return [];
  if (Array.isArray(value)) {
    return value.map(normalize).filter(Boolean);
  }
  if (typeof value === 'string') {
    return value
      .split(',')
      .map(normalize)
      .filter(Boolean);
  }
  if (typeof value === 'object') {
    return Object.entries(value)
      .filter(([, enabled]) => enabled === true)
      .map(([role]) => normalize(role))
      .filter(Boolean);
  }
  return [];
}

function hasRole(profile, roleName) {
  const role = normalize(roleName);
  if (!role) return false;
  const profileRole = normalize(profile?.role);
  if (profileRole === role) return true;
  return [
    ...roleEntries(profile?.roles),
    ...roleEntries(profile?.customClaims?.roles),
    ...roleEntries(profile?.claims?.roles),
  ].includes(role);
}

function hasReserveAccess(profile) {
  return profile?.reserve === true ||
    profile?.isReserve === true ||
    profile?.hasReserveAccess === true ||
    profile?.customClaims?.reserve === true ||
    profile?.customClaims?.isReserve === true ||
    profile?.customClaims?.hasReserveAccess === true ||
    profile?.claims?.reserve === true ||
    profile?.claims?.isReserve === true ||
    profile?.claims?.hasReserveAccess === true ||
    hasRole(profile, 'reserve');
}

async function userHasReserveAccess(decoded) {
  if (hasReserveAccess(decoded)) {
    return true;
  }
  const uid = String(decoded?.uid || '').trim();
  if (!uid) {
    return false;
  }

  let admin;
  try {
    admin = getFirebaseAdmin();
  } catch (error) {
    console.warn('reserve role admin initialization failed', error);
    return false;
  }

  try {
    const authUser = await admin.auth().getUser(uid);
    if (hasReserveAccess(authUser.customClaims || {})) {
      return true;
    }
  } catch (error) {
    console.warn('reserve role custom claim lookup failed', error);
  }

  try {
    const snapshot = await admin.firestore().collection('users').doc(uid).get();
    return hasReserveAccess(snapshot.data() || {});
  } catch (error) {
    console.warn('reserve role profile lookup failed', error);
    return false;
  }
}

async function requireReserveAccess(decoded) {
  if (await userHasReserveAccess(decoded)) {
    return;
  }
  const error = new Error('Reserve listing access required.');
  error.statusCode = 403;
  throw error;
}

module.exports = {
  hasReserveAccess,
  requireReserveAccess,
  roleEntries,
  userHasReserveAccess,
};
