const assert = require('node:assert/strict');
const test = require('node:test');

const { hasReserveAccess, roleEntries } = require('./_firebase_roles');

test('roleEntries accepts arrays, comma strings, and role maps', () => {
  assert.deepEqual(roleEntries(['Reserve', ' user ']), ['reserve', 'user']);
  assert.deepEqual(roleEntries('reserve, admin, '), ['reserve', 'admin']);
  assert.deepEqual(roleEntries({ reserve: true, admin: false }), ['reserve']);
});

test('hasReserveAccess accepts reserve flags and role shapes', () => {
  assert.equal(hasReserveAccess({ reserve: true }), true);
  assert.equal(hasReserveAccess({ isReserve: true }), true);
  assert.equal(hasReserveAccess({ hasReserveAccess: true }), true);
  assert.equal(hasReserveAccess({ role: ' Reserve ' }), true);
  assert.equal(hasReserveAccess({ roles: ['seller', 'reserve'] }), true);
  assert.equal(hasReserveAccess({ roles: 'seller,reserve' }), true);
  assert.equal(hasReserveAccess({ roles: { reserve: true } }), true);
  assert.equal(hasReserveAccess({ customClaims: { reserve: true } }), true);
  assert.equal(hasReserveAccess({ customClaims: { roles: ['reserve'] } }), true);
  assert.equal(hasReserveAccess({ claims: { hasReserveAccess: true } }), true);
  assert.equal(hasReserveAccess({ role: 'user', roles: ['seller'] }), false);
});
