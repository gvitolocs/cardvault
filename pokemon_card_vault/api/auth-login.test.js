const assert = require('node:assert/strict');
const test = require('node:test');
const { authPayload } = require('./auth-login');
const { pknAmountForFiatCents } = require('./_pkn_checkout_pricing');

test('authPayload exposes safe Pokoin bearer metadata', () => {
  const payload = authPayload({
    uid: 'user-123',
    email: 'collector@pokoin.com',
    email_verified: true,
    exp: 1780000000,
    auth_time: 1779996400,
  });

  assert.equal(payload.tokenType, 'Bearer');
  assert.equal(payload.uid, 'user-123');
  assert.equal(payload.email, 'collector@pokoin.com');
  assert.equal(payload.emailVerified, true);
  assert.equal(payload.expiresAt, '2026-05-28T20:26:40.000Z');
  assert.equal(payload.authTime, '2026-05-28T19:26:40.000Z');
});

test('PKN checkout packages use fixed 0.005 USDT reference price', () => {
  assert.equal(pknAmountForFiatCents(500), 1000);
  assert.equal(pknAmountForFiatCents(2500), 5000);
  assert.equal(pknAmountForFiatCents(10000), 20000);
});
