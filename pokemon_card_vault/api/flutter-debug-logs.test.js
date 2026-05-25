const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs({
  marketplaceQuery = async () => ({ rows: [] }),
  authorizeSearchDebugRequest = async () => ({
    uid: 'debug-uid',
    email: 'debug@example.com',
    username: 'debugger',
  }),
} = {}) {
  const target = require.resolve('./flutter-debug-logs');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return { marketplaceQuery };
    }
    if (request === './_search_debug_auth') {
      return { authorizeSearchDebugRequest };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./flutter-debug-logs');
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
    end(value) {
      this.body = value;
      return this;
    },
  };
}

test('flutter debug event input sanitizes urls and secrets', () => {
  const { _test } = loadEndpointWithStubs();
  const input = _test.eventInput(
    {
      sessionId: ' session-1 ',
      eventName: 'Route Changed!',
      category: 'Navigation',
      url: 'https://pokoin.com/card/1?token=secret&q=ok#frag',
      payload: {
        path: '/card/1',
        accessToken: 'secret',
        nested: { password: 'hidden', value: 'kept' },
      },
    },
    { uid: 'admin-uid' },
  );

  assert.equal(input.sessionId, 'session-1');
  assert.equal(input.eventName, 'route_changed');
  assert.equal(input.category, 'navigation');
  assert.equal(input.browserUrl, 'https://pokoin.com/card/1?q=ok#frag');
  assert.deepEqual(input.payload, {
    path: '/card/1',
    nested: { value: 'kept' },
  });
});

test('flutter debug handler requires debug auth before writes', async () => {
  let usedDatabase = false;
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async () => {
      usedDatabase = true;
      return { rows: [] };
    },
    authorizeSearchDebugRequest: async () => {
      const error = new Error('Search debug is not enabled for this account.');
      error.statusCode = 403;
      throw error;
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    headers: {},
    body: { sessionId: 's1', eventName: 'app.start' },
  }, res);

  assert.equal(res.statusCode, 403);
  assert.equal(usedDatabase, false);
});

test('flutter debug POST writes bounded structured event', async () => {
  const calls = [];
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ id: '12', received_at: '2026-05-23T10:00:00.000Z' }] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    headers: {},
    body: {
      sessionId: 'debug-session',
      eventName: 'card_detail.loaded',
      category: 'detail',
      routePath: '/123/pikachu',
      payload: { cardId: '123' },
    },
  }, res);

  assert.equal(res.statusCode, 201);
  assert.equal(res.body.id, '12');
  assert.match(calls[0].sql, /insert into public\.flutter_debug_logs/);
  assert.equal(calls[0].values[1], 'debug-session');
  assert.equal(calls[0].values[6], 'card_detail.loaded');
});

test('flutter debug GET applies filters and limit', async () => {
  const calls = [];
  const { _test } = loadEndpointWithStubs({
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          id: '7',
          received_at: '2026-05-23T10:00:00.000Z',
          session_id: 's1',
          event_name: 'router.changed',
          category: 'navigation',
          payload: { route: '/card/1' },
        }],
      };
    },
  });

  const payload = await _test.readFlutterDebugLogs({
    sessionId: 's1',
    category: 'navigation',
    limit: '5000',
  });

  assert.equal(payload.filters.limit, 5000);
  assert.equal(payload.rows[0].eventName, 'router.changed');
  assert.match(calls[0].sql, /session_id = \$1/);
  assert.match(calls[0].sql, /category = \$2/);
  assert.deepEqual(calls[0].values, ['s1', 'navigation', 5000]);
});

test('flutter debug GET caps very large limits at safe maximum', async () => {
  const calls = [];
  const { _test } = loadEndpointWithStubs({
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [] };
    },
  });

  const payload = await _test.readFlutterDebugLogs({ limit: '9000' });

  assert.equal(payload.filters.limit, 5000);
  assert.deepEqual(calls[0].values, [5000]);
});

test('flutter debug handler responds to GET with no-store JSON', async () => {
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async () => ({
      rows: [{
        id: '7',
        received_at: '2026-05-23T10:00:00.000Z',
        session_id: 's1',
        event_name: 'router.changed',
        category: 'navigation',
        payload: { route: '/card/1' },
      }],
    }),
  });
  const res = responseRecorder();

  await handler({
    method: 'GET',
    url: '/api/flutter-debug-logs?limit=1',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.equal(res.body.filters.limit, 1);
  assert.equal(res.body.rows[0].eventName, 'router.changed');
});
