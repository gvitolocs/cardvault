const assert = require('node:assert/strict');
const test = require('node:test');

process.env.SIGNUP_ENCRYPTION_SECRET = 'test-signup-secret';
process.env.PUBLIC_SITE_URL = 'https://pokoin.com';

const { encryptPassword, hashValue } = require('./_pending_signup');
const { createFakeAdmin, createResponse } = require('./_test_email_signup_harness');
const handler = require('./register-email');

function setup() {
  const admin = createFakeAdmin();
  const sentLinks = [];
  handler._test.setAdminOverride(() => admin);
  handler._test.setSendVerificationOverride(async (options) => {
    sentLinks.push(options);
    return { ok: true, id: 'email-1' };
  });
  return { admin, sentLinks };
}

function release(admin) {
  handler._test.setAdminOverride(null);
  handler._test.setSendVerificationOverride(null);
  return admin;
}

function pendingStore(admin) {
  return admin.__collections.get('pending_email_signups') || new Map();
}

function seedPending(admin, {
  token,
  email,
  username = '',
  password = 'hunter22',
  status = 'pending',
  sentCount = 1,
  lastSentAtMs = Date.now() - 10 * 60 * 1000,
  expiresInMs = 60 * 60 * 1000,
}) {
  const passwordPayload = encryptPassword(password);
  const tokenHash = hashValue(token);
  admin.__collections.set('pending_email_signups', admin.__collections.get('pending_email_signups') || new Map());
  admin.__collections.set('pending_email_signups_by_email', admin.__collections.get('pending_email_signups_by_email') || new Map());
  pendingStore(admin).set(tokenHash, {
    email,
    username,
    passwordPayload,
    redirectPath: '/profile',
    status,
    sentCount,
    lastSentAt: { __timestamp: true, toMillis: () => lastSentAtMs },
    expiresAt: { __timestamp: true, toMillis: () => Date.now() + expiresInMs },
  });
  admin.__collections.get('pending_email_signups_by_email').set(hashValue(email), {
    email,
    tokenHash,
  });
  return { tokenHash, passwordPayload };
}

test('email signup creates pending state only and never a Firebase user', async () => {
  const { admin, sentLinks } = setup();
  const res = createResponse();
  await handler({ method: 'POST', body: { email: 'Ash@Pokoin.com ', password: 'hunter22', username: 'ashketchum', redirectPath: '/marketplace' } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.pending, true);
  assert.equal(res.body.username, 'ashketchum');

  const pendings = [...pendingStore(admin).values()];
  assert.equal(pendings.length, 1);
  assert.equal(pendings[0].email, 'ash@pokoin.com');
  assert.equal(pendings[0].username, 'ashketchum');
  assert.equal(pendings[0].status, 'pending');
  assert.equal(pendings[0].redirectPath, '/marketplace');
  assert.ok(pendings[0].passwordPayload, 'password payload stored');
  assert.notEqual(pendings[0].passwordPayload, 'hunter22', 'password encrypted at rest');

  assert.equal(admin.__userRecords.size, 0, 'no Firebase identity before verification');
  assert.equal(sentLinks.length, 1);
  assert.ok(sentLinks[0].verificationLink.startsWith('https://pokoin.com/auth?signupToken='));
  assert.ok(!sentLinks[0].verificationLink.includes(' '), 'token is url-encoded');
  assert.equal(sentLinks[0].email, 'ash@pokoin.com');
  release();
});

test('signup username is optional and defaults to an auto-assigned handle at finalization', async () => {
  const { admin } = setup();
  const res = createResponse();
  await handler({ method: 'POST', body: { email: 'gary@pokoin.com', password: 'hunter22' } }, res);

  assert.equal(res.statusCode, 200);
  const pendings = [...pendingStore(admin).values()];
  assert.equal(pendings.length, 1);
  assert.equal(pendings[0].username, '');
  assert.equal(admin.__userRecords.size, 0);
  release();
});

test('signup rejects a taken username, an already-registered email, and weak input without pending state', async () => {
  const taken = setup();
  await taken.admin.auth().createUser({ email: 'misty@pokoin.com', password: 'hunter22' });
  await taken.admin.firestore().collection('usernames').doc('misty').set({ uid: 'someone-else' });

  for (const [body, expectedStatus, expectedError] of [
    [{ email: 'ash@pokoin.com', password: 'hunter22', username: 'misty' }, 409, 'Username is already taken.'],
    [{ email: 'misty@pokoin.com', password: 'hunter22' }, 409, 'Email is already registered.'],
    [{ email: 'ash@pokoin.com', password: '123' }, 400, 'Password must be at least 6 characters.'],
    [{ email: 'not-an-email', password: 'hunter22' }, 400, 'Enter a valid email address.'],
  ]) {
    const res = createResponse();
    await handler({ method: 'POST', body }, res);
    assert.equal(res.statusCode, expectedStatus, JSON.stringify(body));
    assert.equal(res.body.error, expectedError);
  }
  assert.equal(pendingStore(taken.admin).size, 0, 'no pending doc on validation failure');
  release();
});

test('resend mints a fresh token, carries the encrypted credentials, and invalidates the old link', async () => {
  const { admin, sentLinks } = setup();
  const first = seedPending(admin, { token: 'token-one', email: 'ash@pokoin.com', username: 'ashketchum' });

  const res = createResponse();
  await handler({ method: 'POST', body: { resend: true, email: 'ash@pokoin.com' } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.resent, true);

  const oldDoc = pendingStore(admin).get(first.tokenHash);
  assert.equal(oldDoc.status, 'superseded', 'old link invalidated');
  assert.equal(pendingStore(admin).size, 2, 'old + new pending docs');

  const fresh = [...pendingStore(admin).values()].find((doc) => doc.status === 'pending');
  assert.equal(fresh.email, 'ash@pokoin.com');
  assert.equal(fresh.username, 'ashketchum');
  assert.equal(fresh.passwordPayload, first.passwordPayload, 'encrypted credentials reused');
  assert.equal(fresh.sentCount, 2);

  const pointer = admin.__collections.get('pending_email_signups_by_email').get(hashValue('ash@pokoin.com'));
  assert.notEqual(pointer.tokenHash, first.tokenHash, 'pointer moved to the fresh doc');

  assert.equal(sentLinks.length, 1);
  const freshToken = decodeURIComponent(sentLinks[0].verificationLink.split('signupToken=')[1]);
  assert.equal(hashValue(freshToken), pointer.tokenHash, 'resent link matches the active pending doc');
  release();
});

test('resend is rate limited per pending signup', async () => {
  const { admin } = setup();
  seedPending(admin, { token: 'token-cool', email: 'ash@pokoin.com', lastSentAtMs: Date.now() - 5 * 1000 });
  const cooldown = createResponse();
  await handler({ method: 'POST', body: { resend: true, email: 'ash@pokoin.com' } }, cooldown);
  assert.equal(cooldown.statusCode, 429);
  assert.ok(cooldown.body.retryAfterSec >= 55);

  seedPending(admin, { token: 'token-capped', email: 'misty@pokoin.com', sentCount: 10, lastSentAtMs: Date.now() - 10 * 60 * 1000 });
  const capped = createResponse();
  await handler({ method: 'POST', body: { resend: true, email: 'misty@pokoin.com' } }, capped);
  assert.equal(capped.statusCode, 429);
  assert.match(capped.body.error, /Too many verification emails/);

  const unknown = createResponse();
  await handler({ method: 'POST', body: { resend: true, email: 'nobody@pokoin.com' } }, unknown);
  assert.equal(unknown.statusCode, 404);
  release();
});

test('register-email method and CORS contract', async () => {
  const { admin } = setup();
  const options = createResponse();
  await handler({ method: 'OPTIONS' }, options);
  assert.equal(options.statusCode, 204);
  assert.equal(options.headers['access-control-allow-methods'], 'POST, OPTIONS');

  const get = createResponse();
  await handler({ method: 'GET' }, get);
  assert.equal(get.statusCode, 405);
  release();
});
