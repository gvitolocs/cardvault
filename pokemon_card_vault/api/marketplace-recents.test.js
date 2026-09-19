const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

const { normalizeRecentIds } = require('./marketplace-recents')._test;

function loadHandler(stubs) {
  const target = require.resolve('./marketplace-recents');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return {
        marketplaceQuery: stubs.marketplaceQuery,
        marketplaceWriteQuery: stubs.marketplaceWriteQuery || stubs.marketplaceQuery,
      };
    }
    if (request === './_firebase') {
      return {
        verifyBearerToken: stubs.verifyBearerToken,
        authErrorResponse: (error) => ({
          statusCode: error.statusCode || 401,
          body: { error: error.message },
        }),
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-recents');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    end() {
      return this;
    },
  };
  return res;
}

test('normalizeRecentIds keeps 24 unique public ids, newest first', () => {
  const ids = normalizeRecentIds(['504094', '504094', 'nope', 293030, '0', ...Array.from({ length: 30 }, (_, i) => String(i + 1))]);
  assert.equal(ids[0], '504094');
  assert.equal(ids[1], '293030');
  assert.equal(ids.length, 24);
  assert.equal(new Set(ids).size, 24);
});

test('GET returns stored recents for the signed-in uid', async () => {
  const calls = [];
  const handler = loadHandler({
    verifyBearerToken: async () => ({ uid: 'user-1' }),
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ card_ids: ['504094', '293030'] }] };
    },
  });
  const res = mockRes();
  await handler({ method: 'GET', headers: { authorization: 'Bearer t' } }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body.cardIds, ['504094', '293030']);
  assert.equal(calls[0].values[0], 'user-1');
});

test('PUT writes the merged list through the 15T writer', async () => {
  const writes = [];
  const handler = loadHandler({
    verifyBearerToken: async () => ({ uid: 'user-1' }),
    marketplaceQuery: async () => ({ rows: [] }),
    marketplaceWriteQuery: async (sql, values) => {
      writes.push({ sql, values });
      return { rows: [] };
    },
  });
  const res = mockRes();
  await handler({
    method: 'PUT',
    headers: { authorization: 'Bearer t' },
    body: { cardId: '790994', cardIds: ['504094', '790994'] },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.match(String(res.headers['Access-Control-Allow-Methods'] || ''), /PUT/);
  assert.deepEqual(res.body.cardIds, ['790994', '504094']);
  assert.match(writes[0].sql, /marketplace_user_recents/);
  assert.equal(writes[0].values[0], 'user-1');
  assert.deepEqual(writes[0].values[1], ['790994', '504094']);
});

test('missing bearer is 401', async () => {
  const handler = loadHandler({
    verifyBearerToken: async () => {
      const error = new Error('Missing Pokoin bearer token.');
      error.statusCode = 401;
      throw error;
    },
    marketplaceQuery: async () => ({ rows: [] }),
  });
  const res = mockRes();
  await handler({ method: 'GET', headers: {} }, res);
  assert.equal(res.statusCode, 401);
});
