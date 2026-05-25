const assert = require('node:assert/strict');
const test = require('node:test');
const { bearerTokenFromRequest } = require('./_firebase');

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
