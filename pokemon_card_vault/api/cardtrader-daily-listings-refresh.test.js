const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs() {
  const target = require.resolve('./cardtrader-daily-listings-refresh');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_cardtrader_client') {
      return {
        cleanToken: (value) => String(value || '').trim(),
        fetchMarketplaceProducts: async () => ({}),
      };
    }
    if (request === './_firebase') {
      return {
        requestHeader: (req, name) => req.headers?.[name.toLowerCase()] || req.headers?.[name] || '',
      };
    }
    if (request === './_marketplace_db') {
      return { marketplaceQuery: async () => ({ rows: [] }) };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./cardtrader-daily-listings-refresh');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function loadRefreshModuleWithStubs(stubs = {}) {
  const target = require.resolve('./_cardtrader_daily_listings_refresh');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_cardtrader_client') {
      return {
        cleanToken: (value) => String(value || '').trim(),
        fetchMarketplaceProducts: stubs.fetchMarketplaceProducts || (async () => ({})),
      };
    }
    if (request === './_marketplace_db') {
      return { marketplaceQuery: async () => ({ rows: [] }) };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./_cardtrader_daily_listings_refresh');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('CardTrader daily refresh dates removed listings to previous UTC day', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(
    _test.removedDayForRefreshDate(new Date('2026-05-24T01:17:00.000Z')),
    '2026-05-23',
  );
});

test('CardTrader daily refresh requires configured cron/admin secret', () => {
  const { _test } = loadEndpointWithStubs();

  assert.throws(
    () => _test.authorizeRefreshRequest({ headers: {} }, {}),
    /refresh secret is not configured/,
  );
  assert.throws(
    () => _test.authorizeRefreshRequest(
      { headers: { authorization: 'Bearer wrong' } },
      { CARDTRADER_DAILY_LISTINGS_SECRET: 'correct' },
    ),
    /access denied/,
  );
  assert.deepEqual(
    _test.authorizeRefreshRequest(
      { headers: { authorization: 'Bearer correct' } },
      { CARDTRADER_DAILY_LISTINGS_SECRET: 'correct' },
    ),
    { type: 'cron_or_admin_secret' },
  );
  assert.deepEqual(
    _test.authorizeRefreshRequest(
      { headers: { authorization: 'Bearer cron-secret' } },
      {
        CARDTRADER_DAILY_LISTINGS_SECRET: 'admin-secret',
        CRON_SECRET: 'cron-secret',
      },
    ),
    { type: 'cron_or_admin_secret' },
  );
});

test('CardTrader daily refresh request options are bounded for dry runs', () => {
  const { _test } = loadEndpointWithStubs();
  const options = _test.requestOptions({
    url: '/api/cardtrader-daily-listings-refresh?dryRun=1&maxBlueprints=999999&maxProducts=9999999&removedDay=2026-05-23&blueprintId=316600&blueprintIds=316601,abc,316602&expansionId=123&language=it&blueprintBatchSize=99999&blueprintConcurrency=999',
    headers: { host: 'pokoin.test' },
  });

  assert.equal(options.dryRun, true);
  assert.equal(options.archiveMissing, false);
  assert.equal(options.maxBlueprints, 100000);
  assert.equal(options.maxProducts, 1000000);
  assert.equal(options.requestDelayMs, 0);
  assert.equal(options.blueprintBatchSize, 1000);
  assert.equal(options.blueprintConcurrency, 50);
  assert.equal(options.removedDay, '2026-05-23');
  assert.deepEqual(options.blueprintIds, [316600, 316601, 316602]);
  assert.equal(options.expansionId, 123);
  assert.equal(options.language, 'it');
});

test('CardTrader daily refresh does not default to a language filter', () => {
  const { _test } = loadEndpointWithStubs();
  const options = _test.requestOptions({
    url: '/api/cardtrader-daily-listings-refresh?dryRun=1&blueprintId=316600',
    headers: { host: 'pokoin.test' },
  });

  assert.equal(options.language, '');
});

test('CardTrader daily refresh resolves global token without exposing seller integrations', () => {
  const { _test } = loadEndpointWithStubs();
  assert.equal(_test.configuredCardTraderApiToken({ CARDTRADER_API_TOKEN: ' global-token ' }), 'global-token');
  assert.equal(_test.configuredCardTraderApiToken({ CARDTRADER_AUTH_TOKEN: ' import-token ' }), 'import-token');
  assert.equal(_test.configuredCardTraderApiToken({
    CARDTRADER_AUTH_TOKEN: ' auth-token ',
    CARDTRADER_API_TOKEN: ' api-token ',
  }), 'auth-token');
});

test('CardTrader shared refresh options support script-style input', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({
    dryRun: true,
    blueprintIds: '316600,316601',
    maxBlueprints: 50,
    maxProducts: 500,
    archiveMissing: undefined,
  });

  assert.equal(options.dryRun, true);
  assert.equal(options.archiveMissing, false);
  assert.equal(options.maxBlueprints, 50);
  assert.equal(options.maxProducts, 500);
  assert.equal(options.requestDelayMs, 300);
  assert.equal(options.blueprintBatchSize, 100);
  assert.equal(options.blueprintConcurrency, 1);
  assert.deepEqual(options.blueprintIds, [316600, 316601]);
});

test('CardTrader shared refresh options bound blueprint batching controls', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({
    blueprintBatchSize: 700,
    blueprintConcurrency: 100,
  });

  assert.equal(options.blueprintBatchSize, 700);
  assert.equal(options.blueprintConcurrency, 50);
});

test('CardTrader shared refresh options allow bounded request delay override', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({
    requestDelayMs: 25,
  });

  assert.equal(options.requestDelayMs, 25);
});

test('CardTrader peer4 refresh script parses safe cron options', () => {
  const script = require('../scripts/refresh-cardtrader-market-listings');
  const options = script.parseArgs([
    '--env-file=/tmp/peer4.env',
    '--dry-run',
    '--blueprint-id=316600',
    '--blueprint-ids=316601,316602',
    '--max-blueprints=25',
    '--max-products=250',
    '--request-delay-ms=750',
    '--blueprint-batch-size=700',
    '--blueprint-concurrency=20',
  ]);

  assert.equal(options.envFile, '/tmp/peer4.env');
  assert.equal(options.dryRun, true);
  assert.deepEqual(options.blueprintIds, [316600, 316601, 316602]);
  assert.equal(options.maxBlueprints, 25);
  assert.equal(options.maxProducts, 250);
  assert.equal(options.requestDelayMs, 750);
  assert.equal(options.blueprintBatchSize, 700);
  assert.equal(options.blueprintConcurrency, 20);
});

test('CardTrader shared refresh fetches blueprint batches with bounded concurrency', async () => {
  const calls = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => {
      calls.push(params.blueprint_id);
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 5));
      inFlight -= 1;
      return {
        [params.blueprint_id]: [{
          id: `listing-${params.blueprint_id}`,
          quantity: 1,
          price_cents: params.blueprint_id,
          currency: 'EUR',
        }],
      };
    },
  });
  const progress = [];
  const result = await refresh.fetchMarketplaceRows('token', refresh.normalizeRefreshOptions({
    blueprintIds: '101,102,103,104,105',
    maxBlueprints: 5,
    maxProducts: 10,
    requestDelayMs: 0,
    blueprintBatchSize: 2,
    blueprintConcurrency: 2,
    onProgress: (event) => progress.push(event),
  }));

  assert.deepEqual(calls, [101, 102, 103, 104, 105]);
  assert.equal(maxInFlight, 2);
  assert.equal(result.rows.length, 5);
  assert.equal(result.fetchedBlueprintIds.length, 5);
  const fetchStart = progress.find((event) => event.event === 'blueprint_fetch_start');
  assert.equal(fetchStart.blueprintBatchSize, 2);
  assert.equal(fetchStart.blueprintConcurrency, 2);
  assert.equal(progress.at(-1).event, 'blueprint_fetch_done');
  assert.equal(progress.at(-1).fetchedBlueprints, 5);
  assert.ok(progress.some((event) => (
    event.event === 'blueprint_fetch_progress' &&
    event.fetchedBlueprints === 2 &&
    event.completedBatches === 1
  )));
});

test('CardTrader peer4 refresh script reports token key presence only', () => {
  const script = require('../scripts/refresh-cardtrader-market-listings');

  assert.equal(script.tokenKeyStatus({}), '');
  assert.equal(script.tokenKeyStatus({ CARDTRADER_AUTH_TOKEN: 'secret' }), 'CARDTRADER_AUTH_TOKEN');
  assert.equal(
    script.tokenKeyStatus({ CARDTRADER_API_TOKEN: 'secret', CARDTRADER_AUTH_TOKEN: 'fallback' }),
    'CARDTRADER_AUTH_TOKEN',
  );
});

test('CardTrader peer4 refresh script loads app env fallback without exposing values', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const script = require('../scripts/refresh-cardtrader-market-listings');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cardtrader-refresh-env-'));
  const primary = path.join(dir, 'primary.env');
  const fallback = path.join(dir, 'fallback.env');
  const originalEnv = { ...process.env };
  try {
    fs.writeFileSync(primary, 'CARDTRADER_AUTH_TOKEN=token-from-primary\n');
    fs.writeFileSync(fallback, 'MARKETPLACE_DATABASE_URL=postgres://fallback.example/db\n');
    delete process.env.CARDTRADER_AUTH_TOKEN;
    delete process.env.MARKETPLACE_DATABASE_URL;
    const loaded = script.loadDefaultFallbackEnvFiles(primary, [fallback]);

    assert.equal(loaded.length, 2);
    assert.equal(process.env.CARDTRADER_AUTH_TOKEN, 'token-from-primary');
    assert.equal(process.env.MARKETPLACE_DATABASE_URL, 'postgres://fallback.example/db');
  } finally {
    process.env = originalEnv;
    fs.rmSync(dir, { force: true, recursive: true });
  }
});

test('CardTrader marketplace product shaping keeps graph and snapshot metadata', () => {
  const { _test } = loadEndpointWithStubs();
  const row = _test.normalizeCardTraderMarketProduct({
    id: 123,
    blueprint_id: 316600,
    quantity: 2,
    price: {
      cents: 1299,
      currency: 'EUR',
    },
    properties_hash: {
      condition: 'Near Mint',
      language: 'English',
      foil_state: 'reverse',
    },
    user: {
      id: 456,
      username: 'Seller One',
      country_code: 'IT',
      user_type: 'professional',
    },
  });

  assert.equal(row.externalListingId, '123');
  assert.equal(row.blueprintId, 316600);
  assert.equal(row.cardtraderBlueprintId, 316600);
  assert.equal(row.pokoinCardId, '316600');
  assert.equal(row.quantity, 2);
  assert.equal(row.price, 12.99);
  assert.equal(row.priceCents, 1299);
  assert.equal(row.currency, 'EUR');
  assert.equal(row.condition, 'Near Mint');
  assert.equal(row.language, 'en');
  assert.equal(row.sellerAccountId, '456');
  assert.equal(row.sellerAccountName, 'Seller One');
  assert.equal(row.sellerCountry, 'IT');
  assert.deepEqual(row.properties, {
    condition: 'Near Mint',
    language: 'English',
    foil_state: 'reverse',
  });
  assert.equal(row.rawMetadata.id, 123);
});

test('CardTrader marketplace payload shaping flattens blueprint keyed products', () => {
  const { _test } = loadEndpointWithStubs();
  const shaped = _test.rowsFromMarketplacePayload({
    316600: [
      { id: 1, quantity: 1, price_cents: 500, price: { currency: 'USD' } },
      { id: 2, blueprint_id: 316600, quantity: 1, price_cents: 700, currency: 'USD' },
    ],
    316601: [
      { id: 3, quantity: 1, price_cents: 900, currency: 'USD' },
    ],
  }, 2);

  assert.deepEqual(shaped.blueprintIds, [316600, 316601]);
  assert.equal(shaped.rows.length, 2);
  assert.equal(shaped.rows[0].blueprintId, 316600);
  assert.equal(shaped.rows[1].externalListingId, '2');
});

test('CardTrader refresh reports derived listing cache count', async () => {
  const refresh = loadRefreshModuleWithStubs();
  const calls = [];
  const result = await refresh.refreshOracleSnapshots({
    rows: [],
    scopeBlueprintIds: [316600],
    removedDay: '2026-05-23',
    archiveMissing: true,
    env: { PKN_CHECKOUT_USDT_PRICE: '0.005' },
    query: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          archived_count: 1,
          deleted_count: 2,
          upserted_count: 3,
          cache_refreshed_count: 4,
        }],
      };
    },
  });

  assert.equal(result.cacheRefreshedCount, 4);
  assert.match(calls[0].sql, /refresh_cardtrader_market_listing_snapshots/);
});

test('CardTrader market refresh SQL includes native listings in homepage cache', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '012_cardtrader_market_listings.sql'),
    'utf8',
  );

  assert.match(sql, /eligible_native as/);
  assert.match(sql, /from public\.marketplace_user_listings/);
  assert.match(sql, /native_listing\.status = 'active'/);
  assert.match(sql, /coalesce\(native_listing\.quantity_available, 0\) > 0/);
  assert.match(sql, /native_listing\.price_pkn > 0/);
  assert.match(sql, /coalesce\(native_listing\.shipping_available, true\) = true/);
  assert.match(sql, /native_listing\.nft_available = true/);
  assert.match(sql, /union all/);
  assert.match(sql, /case when eligible\.provider = 'pokoin_native' then 0 else 1 end/);
  assert.match(sql, /cache\.provider in \(v_provider, 'pokoin_native'\)/);
});
