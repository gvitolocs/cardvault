const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadSearchDebugAuthWithFirebaseStub(firebaseStub) {
  const target = require.resolve('./_search_debug_auth');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_firebase') {
      return firebaseStub;
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./_search_debug_auth');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('search debug treats admin profile flags as eligible', () => {
  const { _test } = loadSearchDebugAuthWithFirebaseStub({});

  assert.equal(_test.hasAdminAccess({ role: 'admin' }), true);
  assert.equal(_test.hasAdminAccess({ role: ' Admin ' }), true);
  assert.equal(_test.hasAdminAccess({ admin: true }), true);
  assert.equal(_test.hasAdminAccess({ isAdmin: true }), true);
  assert.equal(_test.hasAdminAccess({ hasAdminAccess: true }), true);
  assert.equal(_test.hasAdminAccess({ role: 'user' }), false);
});

test('search debug reads configured admin and debug email allowlists', () => {
  const { _test } = loadSearchDebugAuthWithFirebaseStub({});
  const originalAdminEmails = process.env.MARKETPLACE_ADMIN_EMAILS;
  const originalDebugEmails = process.env.MARKETPLACE_DEBUG_EMAILS;
  const originalSignupEmail = process.env.ADMIN_SIGNUP_EMAIL;

  process.env.MARKETPLACE_ADMIN_EMAILS = 'admin@example.com, Second@example.com ';
  process.env.MARKETPLACE_DEBUG_EMAILS = 'debug@example.com';
  process.env.ADMIN_SIGNUP_EMAIL = 'owner@example.com';

  try {
    assert.deepEqual(_test.configuredIdentifiers(), [
      'admin@example.com',
      'second@example.com',
      'debug@example.com',
      'owner@example.com',
    ]);
  } finally {
    restoreEnv('MARKETPLACE_ADMIN_EMAILS', originalAdminEmails);
    restoreEnv('MARKETPLACE_DEBUG_EMAILS', originalDebugEmails);
    restoreEnv('ADMIN_SIGNUP_EMAIL', originalSignupEmail);
  }
});

test('search debug authorizer allows a custom-claim admin and rejects a Firestore admin profile', async () => {
  const claimed = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({
      uid: 'admin-uid',
      email: 'admin-user@example.com',
      admin: true,
    }),
  });
  const user = await claimed.authorizeSearchDebugRequest({
    headers: { authorization: 'Bearer token' },
  });
  assert.equal(user.uid, 'admin-uid');

  const profile = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({
      uid: 'admin-uid',
      email: 'admin-user@example.com',
      username: 'vitologiuseppe17',
    }),
  });
  await assert.rejects(
    () => profile.authorizeSearchDebugRequest({ headers: { authorization: 'Bearer token' } }),
    (error) => error.statusCode === 403,
  );
});

test('search debug authorizer rejects non-admin profiles', async () => {
  const { authorizeSearchDebugRequest } = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({
      uid: 'user-uid',
      email: 'user@example.com',
    }),
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: () => ({
          doc: () => ({
            get: async () => ({
              data: () => ({
                username: 'regular-user',
                role: 'user',
              }),
            }),
          }),
        }),
      }),
    }),
  });

  await assert.rejects(
    () => authorizeSearchDebugRequest({ headers: { authorization: 'Bearer token' } }),
    (error) => {
      assert.equal(error.statusCode, 403);
      assert.equal(error.message, 'Search debug is not enabled for this account.');
      return true;
    },
  );
});

function restoreEnv(name, value) {
  if (value === undefined) {
    delete process.env[name];
    return;
  }
  process.env[name] = value;
}

function profileStub(profile) {
  return () => ({
    firestore: () => ({
      collection: () => ({
        doc: () => ({ get: async () => ({ data: () => profile }) }),
      }),
    }),
  });
}

async function assertDenied(authorize) {
  await assert.rejects(
    () => authorize({ headers: { authorization: 'Bearer token' } }),
    (error) => error.statusCode === 403,
  );
}

test('search debug ignores a display name or profile username set to the operator handle', async () => {
  const { authorizeSearchDebugRequest } = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({
      uid: 'attacker-uid',
      email: 'attacker@example.com',
      email_verified: true,
      name: 'vitologiuseppe17',
    }),
    getFirebaseAdmin: profileStub({ username: 'vitologiuseppe17' }),
  });
  await assertDenied(authorizeSearchDebugRequest);
});

test('search debug requires a verified token email for the operator allowlist', async () => {
  const unverified = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({ uid: 'x', email: 'pokoinpos@gmail.com', email_verified: false }),
    getFirebaseAdmin: profileStub({}),
  });
  await assertDenied(unverified.authorizeSearchDebugRequest);

  const verified = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({ uid: 'op', email: 'PokoinPOS@gmail.com', email_verified: true }),
    getFirebaseAdmin: () => {
      throw new Error('profile lookup not needed');
    },
  });
  const user = await verified.authorizeSearchDebugRequest({ headers: { authorization: 'Bearer token' } });
  assert.equal(user.uid, 'op');
});
