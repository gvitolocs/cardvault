const assert = require('node:assert/strict');
const test = require('node:test');
const {
  assertActivePasswordAccount,
  bearerTokenFromRequest,
  passwordAccountRequiresVerification,
} = require('./_firebase');

test('bearerTokenFromRequest extracts a Pokoin bearer token', () => {
  const token = bearerTokenFromRequest({
    headers: {
      authorization: 'Bearer abc.def.ghi',
    },
  });

  assert.equal(token, 'abc.def.ghi');
});

test('bearerTokenFromRequest rejects missing or non-bearer authorization', () => {
  assert.equal(bearerTokenFromRequest({}), '');
  assert.equal(bearerTokenFromRequest({ headers: undefined }), '');
  assert.equal(bearerTokenFromRequest({ headers: {} }), '');
  assert.equal(
    bearerTokenFromRequest({
      headers: {
        authorization: 'Basic abc',
      },
    }),
    '',
  );
});

test('bearerTokenFromRequest accepts Vercel and Fetch-style headers', () => {
  assert.equal(
    bearerTokenFromRequest({
      headers: {
        Authorization: 'Bearer mixed.case.token',
      },
    }),
    'mixed.case.token',
  );
  assert.equal(
    bearerTokenFromRequest({
      headers: new Headers({
        authorization: 'Bearer fetch.header.token',
      }),
    }),
    'fetch.header.token',
  );
});

test('only unverified email/password identities require verification', () => {
  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'password' },
    email_verified: false,
  }), true);
  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'password' },
  }), true, 'missing email_verified claim counts as unverified');

  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'password' },
    email_verified: true,
  }), false, 'verified email/password identities are active');
  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'password' },
    email_verified: false,
    pok_email_verified: true,
  }), false, 'grandfathered legacy claims are active');

  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'google.com' },
    email_verified: false,
  }), false, 'Google keeps its existing semantics');
  assert.equal(passwordAccountRequiresVerification({
    firebase: { sign_in_provider: 'custom' },
  }), false, 'wallet custom tokens keep their existing semantics');
  assert.equal(passwordAccountRequiresVerification({}), false, 'missing provider detection never rejects');
});

test('assertActivePasswordAccount denies unverified password identities only when enforcement is on', () => {
  const unverified = { firebase: { sign_in_provider: 'password' }, email_verified: false };
  const verified = { firebase: { sign_in_provider: 'password' }, email_verified: true };
  const google = { firebase: { sign_in_provider: 'google.com' } };

  assert.doesNotThrow(() => assertActivePasswordAccount(unverified, { requireVerified: false }));
  assert.doesNotThrow(() => assertActivePasswordAccount(verified, { requireVerified: true }));
  assert.doesNotThrow(() => assertActivePasswordAccount(google, { requireVerified: true }));

  assert.throws(
    () => assertActivePasswordAccount(unverified, { requireVerified: true }),
    (error) => error.statusCode === 403 && error.code === 'auth/pokoin-email-not-verified',
  );
});
