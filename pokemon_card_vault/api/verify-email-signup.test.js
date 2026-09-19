const assert = require('node:assert/strict');
const test = require('node:test');

process.env.SIGNUP_ENCRYPTION_SECRET = 'test-signup-secret';
process.env.PUBLIC_SITE_URL = 'https://pokoin.com';

const { encryptPassword, hashValue } = require('./_pending_signup');
const { createFakeAdmin, createResponse } = require('./_test_email_signup_harness');
const handler = require('./verify-email-signup');

function setup() {
  const admin = createFakeAdmin();
  handler._test.setAdminOverride(() => admin);
  const notifications = [];
  const welcomes = [];
  handler._test.setSendNotificationOverride(async (options) => {
    notifications.push(options);
    return { ok: true };
  });
  handler._test.setSendWelcomeOverride(async (options) => {
    welcomes.push(options);
    return { ok: true };
  });
  return { admin, notifications, welcomes };
}

function release() {
  handler._test.setAdminOverride(null);
  handler._test.setSendNotificationOverride(null);
  handler._test.setSendWelcomeOverride(null);
}

function seedPending(admin, {
  token,
  email,
  username = '',
  password = 'hunter22',
  status = 'pending',
  expiresInMs = 60 * 60 * 1000,
  redirectPath = '/profile',
}) {
  admin.__collections.set('pending_email_signups', admin.__collections.get('pending_email_signups') || new Map());
  admin.__collections.get('pending_email_signups').set(hashValue(token), {
    email,
    username,
    passwordPayload: encryptPassword(password),
    redirectPath,
    status,
    expiresAt: { __timestamp: true, toMillis: () => Date.now() + expiresInMs },
  });
}

async function verify(token, body = {}) {
  const res = createResponse();
  await handler({ method: 'POST', body: { token, ...body } }, res);
  return res;
}

test('verification finalizes the Pokoin account exactly once', async () => {
  const { admin, notifications, welcomes } = setup();
  seedPending(admin, { token: 'token-A', email: 'ash@pokoin.com', username: 'ashketchum', redirectPath: '/marketplace' });

  const res = await verify('token-A');
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.username, 'ashketchum');
  assert.equal(res.body.redirectPath, '/marketplace');
  assert.equal(res.body.customToken, `custom-token-${res.body.uid}`);

  const [user] = [...admin.__userRecords.values()];
  assert.equal(user.email, 'ash@pokoin.com');
  assert.equal(user.emailVerified, true, 'identity born verified');
  assert.equal(user.displayName, 'ashketchum');
  assert.equal(user.customClaims.pok_email_verified, true, 'finalization stamp is on the identity');

  const usernameClaim = (await admin.firestore().collection('usernames').doc('ashketchum').get());
  assert.equal(usernameClaim.data().uid, user.uid);
  const profile = (await admin.firestore().collection('users').doc(user.uid).get()).data();
  assert.equal(profile.email, 'ash@pokoin.com');
  assert.equal(profile.username, 'ashketchum');
  assert.ok((await admin.firestore().collection('balances').doc(user.uid).get()).exists);

  const pendingDoc = admin.__collections.get('pending_email_signups').get(hashValue('token-A'));
  assert.equal(pendingDoc.status, 'completed');
  assert.equal(pendingDoc.uid, user.uid);

  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].provider, 'email_password');
  assert.equal(welcomes.length, 1);
  release();
});

test('verification callback retry is harmless and creates no duplicates', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-retry', email: 'ash@pokoin.com', username: 'ashketchum' });

  const first = await verify('token-retry');
  assert.equal(first.statusCode, 200);
  const second = await verify('token-retry');
  assert.equal(second.statusCode, 400);
  assert.equal(second.body.code, 'already_verified');
  assert.match(second.body.error, /Please sign in/);

  assert.equal(admin.__userRecords.size, 1, 'still exactly one identity');
  assert.equal(admin.__collections.get('usernames').size, 1, 'still exactly one username claim');
  release();
});

test('invalid and expired verification tokens fail cleanly without creating anything', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-old', email: 'ash@pokoin.com', username: 'ashketchum', expiresInMs: -1000 });

  const unknown = await verify('never-issued');
  assert.equal(unknown.statusCode, 400);
  assert.equal(unknown.body.code, 'invalid_token');

  const expired = await verify('token-old');
  assert.equal(expired.statusCode, 400);
  assert.equal(expired.body.code, 'expired_token');
  assert.match(expired.body.error, /expired/i);

  assert.equal(admin.__userRecords.size, 0);
  assert.equal(admin.__collections.get('pending_email_signups').get(hashValue('token-old')).status, 'expired');
  release();
});

test('a username claimed between signup and verification falls back to a unique handle', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-clash', email: 'ash@pokoin.com', username: 'ashketchum' });
  await admin.auth().createUser({ email: 'other@pokoin.com', password: 'hunter22' });
  const squatter = [...admin.__userRecords.values()][0];
  await admin.firestore().collection('usernames').doc('ashketchum').set({ uid: squatter.uid });

  const res = await verify('token-clash');
  assert.equal(res.statusCode, 200, 'verification must not fail on a username clash');
  assert.notEqual(res.body.username, 'ashketchum');
  assert.match(res.body.username, /^ashketchum\d*$/);

  const claim = (await admin.firestore().collection('usernames').doc(res.body.username).get()).data();
  assert.equal(claim.uid, res.body.uid);
  release();
});

test('signups without a username get an auto-assigned handle from the email', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-auto', email: 'gary.oak@pokoin.com', username: '' });

  const res = await verify('token-auto');
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.username, 'garyoak');
  assert.equal((await admin.firestore().collection('usernames').doc('garyoak').get()).data().uid, res.body.uid);
  release();
});

test('a database failure during finalization deletes the identity and the link stays valid for retry', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-dbfail', email: 'ash@pokoin.com', username: 'ashketchum' });

  admin.__failNextSet = 'balances';
  const failed = await verify('token-dbfail');
  assert.equal(failed.statusCode, 500);
  assert.equal(admin.__userRecords.size, 0, 'partial finalization rolled back');
  assert.equal(
    admin.__collections.get('pending_email_signups').get(hashValue('token-dbfail')).status,
    'pending',
    'pending doc still claims the signup',
  );

  const retried = await verify('token-dbfail');
  assert.equal(retried.statusCode, 200, 'same link succeeds after the transient failure');
  assert.equal(admin.__userRecords.size, 1);
  release();
});

test('a concurrent finalization of the same signup resolves to a sign-in prompt, not a duplicate', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-race', email: 'ash@pokoin.com', username: 'ashketchum' });

  // Simulate the losing tab: the email check passes, but createUser loses the
  // race against the other tab's createUser.
  const realAuth = admin.auth();
  admin.auth = () => ({
    ...realAuth,
    getUserByEmail: async () => {
      throw Object.assign(new Error('auth/user-not-found'), { code: 'auth/user-not-found' });
    },
    createUser: async () => {
      throw Object.assign(new Error('auth/email-already-exists'), { code: 'auth/email-already-exists' });
    },
  });

  const res = await verify('token-race');
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.code, 'already_verified');
  assert.match(res.body.error, /sign in/i);
  assert.equal(
    admin.__collections.get('pending_email_signups').get(hashValue('token-race')).status,
    'pending',
  );
  release();
});

test('verify-email-signup method and CORS contract', async () => {
  setup();
  const options = createResponse();
  await handler({ method: 'OPTIONS' }, options);
  assert.equal(options.statusCode, 204);

  const get = createResponse();
  await handler({ method: 'GET' }, get);
  assert.equal(get.statusCode, 405);

  const missing = createResponse();
  await handler({ method: 'POST', body: {} }, missing);
  assert.equal(missing.statusCode, 400);
  release();
});
