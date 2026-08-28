const assert = require('node:assert/strict');
const test = require('node:test');

const { _test } = require('./_api_observability');

test('observability logs server errors and slow requests by default', () => {
  assert.equal(_test.shouldLogRequest({
    durationMs: 10,
    statusCode: 500,
    error: null,
  }), true);
  assert.equal(_test.shouldLogRequest({
    durationMs: 1000,
    statusCode: 200,
    error: null,
  }), true);
  assert.equal(_test.shouldLogRequest({
    durationMs: 10,
    statusCode: 200,
    error: null,
  }), false);
});

test('observability can be disabled for structural tests', () => {
  const original = process.env.ORACLE_API_OBSERVABILITY;
  process.env.ORACLE_API_OBSERVABILITY = '0';
  try {
    assert.equal(_test.shouldLogRequest({
      durationMs: 5000,
      statusCode: 500,
      error: new Error('boom'),
    }), false);
  } finally {
    if (original === undefined) {
      delete process.env.ORACLE_API_OBSERVABILITY;
    } else {
      process.env.ORACLE_API_OBSERVABILITY = original;
    }
  }
});

test('syntax errors are reported as client JSON errors', () => {
  assert.equal(
    _test.statusCodeForObservation({ statusCode: 200 }, new SyntaxError('bad json')),
    400,
  );
  assert.equal(
    _test.statusCodeForObservation({ statusCode: 200 }, Object.assign(new Error('too large'), { statusCode: 413 })),
    413,
  );
});

test('safe path strips query strings', () => {
  assert.equal(
    _test.safePath({
      url: '/api/marketplace-home?debug=true',
      headers: { host: 'pokoin.com' },
    }),
    '/api/marketplace-home',
  );
});
