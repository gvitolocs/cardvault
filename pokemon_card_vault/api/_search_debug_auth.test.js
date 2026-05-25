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

test('search debug authorizer allows Firestore admin profiles', async () => {
  const { authorizeSearchDebugRequest } = loadSearchDebugAuthWithFirebaseStub({
    verifyBearerToken: async () => ({
      uid: 'admin-uid',
      email: 'admin-user@example.com',
    }),
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: (name) => {
          assert.equal(name, 'users');
          return {
            doc: (uid) => {
              assert.equal(uid, 'admin-uid');
              return {
                get: async () => ({
                  data: () => ({
                    username: 'admin-user',
                    role: 'admin',
                  }),
                }),
              };
            },
          };
        },
      }),
    }),
  });

  const user = await authorizeSearchDebugRequest({
    headers: { authorization: 'Bearer token' },
  });

  assert.deepEqual(user, {
    uid: 'admin-uid',
    email: 'admin-user@example.com',
    username: 'admin-user',
  });
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
