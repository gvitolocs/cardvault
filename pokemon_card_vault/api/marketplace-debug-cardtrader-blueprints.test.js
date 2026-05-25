const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs({
  marketplaceQuery = async () => {
    throw new Error('database should not be used by helper tests');
  },
  authorizeSearchDebugRequest = async () => ({
    uid: 'debug-user',
    email: 'debug@example.com',
    username: 'debugger',
  }),
} = {}) {
  const target = require.resolve('./marketplace-debug-cardtrader-blueprints');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return {
        marketplaceQuery,
      };
    }
    if (request === './_search_debug_auth') {
      return {
        authorizeSearchDebugRequest,
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-debug-cardtrader-blueprints');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('CardTrader debug job payload defaults to safe Oracle dry-run', () => {
  const { _test } = loadEndpointWithStubs();
  const payload = _test.requestPayload({});

  assert.equal(payload.game, 'pokemon');
  assert.equal(payload.mode, 'dry_run');
  assert.equal(payload.streamAll, true);
  assert.equal(payload.limit, 'all');
  assert.equal(payload.images, false);
  assert.equal(payload.refresh, false);
  assert.equal(payload.syncSearch, false);
});

test('CardTrader debug apply payload is bounded and keeps numeric expansion ids', () => {
  const { _test } = loadEndpointWithStubs();
  const payload = _test.requestPayload({
    game: 'Pokemon TCG!',
    mode: 'apply',
    expansionIds: ['4611', 'bad', 4639],
    limit: '999999',
    concurrency: 99,
    imageConcurrency: 99,
    imageChunkSize: 999,
  });

  assert.equal(payload.game, 'pokemon_tcg');
  assert.equal(payload.mode, 'apply');
  assert.equal(payload.streamAll, false);
  assert.deepEqual(payload.expansionIds, [4611, 4639]);
  assert.equal(payload.limit, '50000');
  assert.equal(payload.concurrency, 20);
  assert.equal(payload.imageConcurrency, 12);
  assert.equal(payload.imageChunkSize, 200);
  assert.equal(payload.images, true);
  assert.equal(payload.refresh, true);
  assert.equal(payload.syncSearch, true);
});

test('CardTrader debug publicJob hides requester identity and secrets', () => {
  const { _test } = loadEndpointWithStubs();
  const job = _test.publicJob({
    job_id: 'cti_1',
    game: 'pokemon',
    mode: 'dry_run',
    status: 'running',
    request_payload: { game: 'pokemon', mode: 'dry_run' },
    progress: { counts: { missingRaw: 2 } },
    summary: {},
    requested_by_email: 'admin@example.com',
    error_message: '',
  });

  assert.equal(job.jobId, 'cti_1');
  assert.equal(job.active, true);
  assert.equal(job.requestedByEmail, undefined);
  assert.deepEqual(job.progress, { counts: { missingRaw: 2 } });
});

test('CardTrader debug handler rejects before database when auth fails', async () => {
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
  const res = mockResponse();

  await handler({ method: 'GET', url: '/api/marketplace-debug-cardtrader-blueprints', headers: {} }, res);

  assert.equal(res.statusCode, 403);
  assert.equal(usedDatabase, false);
  assert.match(res.body.error, /Search debug is not enabled/);
});

test('CardTrader debug handler queues dry-run job without running import', async () => {
  const calls = [];
  const handler = loadEndpointWithStubs({
    marketplaceQuery: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          job_id: values[6],
          game: values[0],
          mode: values[1],
          status: 'queued',
          request_payload: JSON.parse(values[5]),
          progress: {},
          summary: {},
          error_message: '',
        }],
      };
    },
  });
  const res = mockResponse();

  await handler({
    method: 'POST',
    url: '/api/marketplace-debug-cardtrader-blueprints',
    headers: {},
    body: { game: 'pokemon', mode: 'dry_run' },
  }, res);

  assert.equal(res.statusCode, 202);
  assert.equal(res.body.enqueued, true);
  assert.equal(res.body.job.status, 'queued');
  assert.match(calls[0].sql, /insert into public\.marketplace_cardtrader_import_jobs/);
  assert.doesNotMatch(calls[0].sql, /cardtrader_pokemon_blueprints|blueprints\/export/);
});

function mockResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(name, value) {
      this.headers[name] = value;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}
