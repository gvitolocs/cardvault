const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs({
  marketplaceQuery = async () => ({ rows: [] }),
  verifyIdToken = async () => ({ uid: 'user-1' }),
} = {}) {
  const target = require.resolve('./user-current-page');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return { marketplaceQuery };
    }
    if (request === './_firebase') {
      return {
        bearerTokenFromRequest: (req) => {
          const header = req.headers?.authorization || req.headers?.Authorization || '';
          return String(header).startsWith('Bearer ') ? String(header).slice('Bearer '.length).trim() : '';
        },
        getFirebaseAdmin: () => ({
          auth: () => ({ verifyIdToken }),
        }),
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./user-current-page');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
  };
}

test('current page path sanitizer accepts internal Pokoin paths only', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(
    _test.cleanInternalPath('/marketplace/en/cards/633200/leafeon?from=assistant'),
    '/marketplace/en/cards/633200/leafeon?from=assistant',
  );
  assert.equal(
    _test.cleanInternalPath('https://pokoin.com/marketplace/en/cards/633200/leafeon'),
    '/marketplace/en/cards/633200/leafeon',
  );
  assert.equal(_test.cleanInternalPath('https://example.com/marketplace'), '');
  assert.equal(_test.cleanInternalPath('//pokoin.com/marketplace'), '');
  assert.equal(_test.cleanInternalPath('/marketplace/\n/cards'), '');
});

test('current page POST upserts anonymous session-scoped path', async () => {
  const calls = [];
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          session_id: values[0],
          user_uid: values[1],
          path: values[2],
          source: values[3],
          updated_at: '2026-05-24T10:00:00.000Z',
        }],
      };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    url: '/api/user-current-page',
    headers: { host: 'pokoin.com' },
    body: {
      sessionId: 'flutter-12345678-1',
      path: '/marketplace/en/cards/633200/leafeon',
      source: 'assistant-navigate',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.page.path, '/marketplace/en/cards/633200/leafeon');
  assert.match(calls[0].sql, /insert into public\.assistant_user_current_pages/);
  assert.deepEqual(calls[0].values, [
    'flutter-12345678-1',
    '',
    '/marketplace/en/cards/633200/leafeon',
    'assistant-navigate',
  ]);
});

test('current page GET scopes authenticated reads to user uid', async () => {
  const calls = [];
  const handler = loadEndpointWithStubs({
    verifyIdToken: async (token) => ({ uid: `uid-${token}` }),
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          session_id: 'flutter-12345678-1',
          user_uid: 'uid-token-1',
          path: '/marketplace/en/cards/633200/leafeon',
          source: 'assistant-navigate',
          updated_at: '2026-05-24T10:00:00.000Z',
        }],
      };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'GET',
    url: '/api/user-current-page?sessionId=flutter-12345678-1',
    headers: {
      host: 'pokoin.com',
      authorization: 'Bearer token-1',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.authenticated, true);
  assert.equal(res.body.page.userUid, 'uid-token-1');
  assert.match(calls[0].sql, /user_uid = \$2/);
  assert.deepEqual(calls[0].values, ['flutter-12345678-1', 'uid-token-1']);
});

test('current page POST rejects unsafe external paths before database write', async () => {
  let usedDatabase = false;
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async () => {
      usedDatabase = true;
      return { rows: [] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    url: '/api/user-current-page',
    headers: { host: 'pokoin.com' },
    body: {
      sessionId: 'flutter-12345678-1',
      path: 'https://evil.example/cards/1',
    },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.equal(usedDatabase, false);
  assert.match(res.body.error, /safe internal Pokoin path/);
});
