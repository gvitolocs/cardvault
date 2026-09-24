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
      return {
        marketplaceQuery: stubs.marketplaceQuery || (async () => ({ rows: [] })),
        getMarketplacePool: stubs.getMarketplacePool || (() => {
          throw new Error('getMarketplacePool should not be used in unit tests');
        }),
      };
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
  assert.equal(options.maxProducts, 9999999);
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
  assert.equal(options.requestDelayMs, 200);
  assert.equal(options.blueprintBatchSize, 100);
  assert.equal(options.blueprintConcurrency, 1);
  assert.deepEqual(options.blueprintIds, [316600, 316601]);
});

test('CardTrader shared refresh options bound blueprint batching controls', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({
    blueprintBatchSize: 700,
    blueprintConcurrency: 100,
    expansionConcurrency: 99,
    persistConcurrency: 99,
  });

  assert.equal(options.blueprintBatchSize, 700);
  assert.equal(options.blueprintConcurrency, 50);
  assert.equal(options.expansionConcurrency, 16);
  assert.equal(options.persistConcurrency, 4);
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

test('CardTrader peer4 refresh script parses expansion import options', () => {
  const script = require('../scripts/refresh-cardtrader-market-listings');
  const options = script.parseArgs([
    '--by-expansion',
    '--no-finalize',
    '--expansion-id=4611',
    '--expansion-ids=4639,4640',
    '--max-expansions=50',
    '--expansion-concurrency=4',
    '--persist-concurrency=2',
    '--shard-count=2',
    '--shard-index=1',
    '--complete-book',
    '--min-expansion-id=3997',
  ]);

  assert.equal(options.byBlueprint, false);
  assert.equal(options.finalize, false);
  assert.equal(options.expansionId, 4611);
  assert.deepEqual(options.expansionIds, [4611, 4639, 4640]);
  assert.equal(options.maxExpansions, 50);
  assert.equal(options.expansionConcurrency, 4);
  assert.equal(options.persistConcurrency, 2);
  assert.equal(options.expansionShardCount, 2);
  assert.equal(options.expansionShardIndex, 1);
  assert.equal(options.completeBook, true);
  assert.equal(options.minExpansionId, 3997);
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

test('CardTrader expansion refresh overlaps marketplace fetches', async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const expansionIds = [];
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      expansionIds.push(params.expansion_id);
      await new Promise((resolve) => setTimeout(resolve, 40));
      inFlight -= 1;
      return { 101: [] };
    },
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('group by expansion_id')) {
        return {
          rows: [
            { expansion_id: 11, blueprint_ids: [101] },
            { expansion_id: 12, blueprint_ids: [102] },
            { expansion_id: 13, blueprint_ids: [103] },
          ],
        };
      }
      return { rows: [] };
    },
  });

  await refresh.runRefresh({
    dryRun: true,
    expansionIds: [11, 12, 13],
    expansionConcurrency: 3,
    requestDelayMs: 0,
    finalize: false,
  }, { CARDTRADER_AUTH_TOKEN: 'token' });

  assert.deepEqual(expansionIds.slice().sort((a, b) => a - b), [11, 12, 13]);
  assert.equal(maxInFlight, 3);
});

test('CardTrader expansion refresh persists overlapping sets', async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => ({
      [100 + Number(params.expansion_id)]: [{
        id: `listing-${params.expansion_id}`,
        quantity: 1,
        price_cents: 100,
      }],
    }),
    getMarketplacePool: () => ({
      connect: async () => {
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        return {
          query: async () => {
            await new Promise((resolve) => setTimeout(resolve, 40));
            return {
              rows: [{
                archived_count: 0,
                deleted_count: 0,
                upserted_count: 1,
                cache_refreshed_count: 0,
              }],
            };
          },
          on: () => {},
          release: () => {
            inFlight -= 1;
          },
        };
      },
    }),
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('group by expansion_id')) {
        return {
          rows: [
            { expansion_id: 11, blueprint_ids: [111] },
            { expansion_id: 12, blueprint_ids: [112] },
            { expansion_id: 13, blueprint_ids: [113] },
          ],
        };
      }
      return { rows: [] };
    },
  });

  await refresh.runRefresh({
    dryRun: false,
    expansionIds: [11, 12, 13],
    expansionConcurrency: 3,
    persistConcurrency: 3,
    requestDelayMs: 0,
    finalize: false,
  }, { CARDTRADER_AUTH_TOKEN: 'token' });

  assert.equal(maxInFlight, 3);
});

test('CardTrader expansion refresh can resume from a minimum expansion id', async () => {
  const expansionIds = [];
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => {
      expansionIds.push(params.expansion_id);
      return { 101: [] };
    },
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('group by expansion_id')) {
        return {
          rows: [
            { expansion_id: 11, blueprint_ids: [101] },
            { expansion_id: 12, blueprint_ids: [102] },
            { expansion_id: 3997, blueprint_ids: [103] },
            { expansion_id: 4001, blueprint_ids: [104] },
          ],
        };
      }
      return { rows: [] };
    },
  });

  await refresh.runRefresh({
    dryRun: true,
    minExpansionId: 3997,
    maxExpansions: 100,
    expansionConcurrency: 2,
    requestDelayMs: 0,
    finalize: false,
  }, { CARDTRADER_AUTH_TOKEN: 'token' });

  assert.deepEqual(expansionIds.slice().sort((a, b) => a - b), [3997, 4001]);
});

test('CardTrader expansion refresh splits catalog across peer shards', async () => {
  const expansionIds = [];
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => {
      expansionIds.push(params.expansion_id);
      return { 101: [] };
    },
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('group by expansion_id')) {
        return {
          rows: [
            { expansion_id: 10, blueprint_ids: [101] },
            { expansion_id: 11, blueprint_ids: [102] },
            { expansion_id: 12, blueprint_ids: [103] },
            { expansion_id: 13, blueprint_ids: [104] },
          ],
        };
      }
      return { rows: [] };
    },
  });

  await refresh.runRefresh({
    dryRun: true,
    expansionIds: [10, 11, 12, 13],
    expansionShardCount: 2,
    expansionShardIndex: 1,
    maxExpansions: 100,
    expansionConcurrency: 2,
    requestDelayMs: 0,
    finalize: false,
  }, { CARDTRADER_AUTH_TOKEN: 'token' });

  assert.deepEqual(expansionIds.slice().sort((a, b) => a - b), [11, 13]);
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
  assert.equal(row.pokoinCardId, '633200');
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

test('CardTrader snapshots stamp reverse, first edition, and graded comments only', () => {
  const refresh = loadRefreshModuleWithStubs();
  const reverseRow = refresh.slimCardTraderMarketProduct({
    id: 1,
    blueprint_id: 10,
    properties_hash: { pokemon_reverse: true, condition: 'Near Mint' },
    description: 'Check my store, more cards available! :3',
  });
  assert.equal(reverseRow.properties_hash.foil_state, 'reverse');
  assert.equal(reverseRow.properties_hash.seller_comment, undefined);

  const first = refresh.slimCardTraderMarketProduct({
    id: 2,
    blueprint_id: 10,
    properties_hash: { first_edition: true },
    description: 'Unlimited print note',
  });
  assert.equal(first.properties_hash.first_edition, true);
  assert.equal(first.properties_hash.seller_comment, undefined);

  const graded = refresh.slimCardTraderMarketProduct({
    id: 3,
    blueprint_id: 10,
    graded: true,
    description: 'Tiny edge whitening',
  });
  assert.equal(graded.properties_hash.seller_comment, 'Tiny edge whitening');
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

test('CardTrader expansion shaping keeps only the cheapest 25 listings per blueprint', () => {
  const refresh = loadRefreshModuleWithStubs();
  const products = Array.from({ length: 30 }, (_, index) => ({
    id: index + 1,
    quantity: index === 0 ? 12 : 1,
    price_cents: 3000 - index,
    currency: 'EUR',
    user: { id: `seller-${index % 7}` },
  }));
  const shaped = refresh.rowsFromMarketplacePayload({ 316600: products });

  assert.equal(shaped.rows.length, 25);
  assert.equal(shaped.rows[0].externalListingId, '30');
  assert.equal(shaped.rows[0].priceCents, 2971);
  assert.equal(shaped.rows[24].externalListingId, '6');
  assert.equal(shaped.rows[24].priceCents, 2995);
  assert.equal(shaped.blueprintIds.includes(316600), true);
  assert.equal(shaped.populations.length, 1);
  assert.equal(shaped.populations[0].blueprintId, 316600);
  assert.equal(shaped.populations[0].listingCount, 30);
  assert.equal(shaped.populations[0].listedQuantity, 41);
  assert.equal(shaped.populations[0].sellerCount, 7);
  assert.equal(shaped.populations[0].capped, true);
});

test('complete-book observations archive missing listings; partial ones never do', () => {
  const refresh = loadRefreshModuleWithStubs();
  // D000070: validity = complete-book AND not truncated. Expansion dumps and
  // by-blueprint runs are both completeBook once the cheap-25 trim is gone.
  assert.equal(refresh.shouldArchiveMissingSales({
    archiveMissing: true,
    byBlueprint: false,
    completeBook: true,
  }, { truncated: false }), true);
  assert.equal(refresh.shouldArchiveMissingSales({
    archiveMissing: true,
    byBlueprint: true,
    completeBook: true,
  }, { truncated: false }), true);
  assert.equal(refresh.shouldArchiveMissingSales({
    archiveMissing: true,
    byBlueprint: true,
    completeBook: true,
  }, { truncated: true }), false);
  assert.equal(refresh.shouldArchiveMissingSales({
    archiveMissing: true,
    byBlueprint: false,
    completeBook: false,
  }, { truncated: false }), false);
  assert.equal(refresh.shouldArchiveMissingSales({
    archiveMissing: false,
    byBlueprint: false,
    completeBook: true,
  }, { truncated: false }), false);
});

test('a CardTrader rejection after a successful refresh call is retried', () => {
  const refresh = loadRefreshModuleWithStubs();

  const rejected = Object.assign(new Error('CardTrader rejected this API token.'), {
    statusCode: 400,
  });
  assert.equal(refresh.isCardTraderAuthenticationRejection(rejected), true);
  assert.equal(refresh.isTransientCardTraderFetchError(rejected), true);
  assert.equal(
    refresh.isTransientCardTraderFetchError(
      Object.assign(new Error('CardTrader request failed with HTTP 404.'), { statusCode: 502 }),
    ),
    false,
  );
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

test('CardTrader refresh options keep expansionId unset without an expansion flag', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({
    blueprintIds: '101,102',
  });

  assert.equal(options.expansionId, null);
  assert.deepEqual(options.expansionIds, []);
});

test('CardTrader dry-run without ids only probes one expansion', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeRefreshOptions({ dryRun: true });

  assert.equal(options.maxExpansions, 1);
  assert.equal(options.byBlueprint, false);
  assert.equal(options.finalize, false);
  assert.equal(options.recordAskObservations, false);
  assert.equal(options.expansionConcurrency, 1);
});

test('CardTrader expansion refresh uses one marketplace call and keeps sold-out blueprints in scope', async () => {
  const calls = [];
  const refresh = loadRefreshModuleWithStubs({
    fetchMarketplaceProducts: async (_token, params) => {
      calls.push(params);
      return {
        316600: [{
          id: 11,
          blueprint_id: 316600,
          quantity: 2,
          price: { cents: 500, currency: 'EUR' },
        }],
      };
    },
  });
  const result = await refresh.fetchMarketplaceRowsForExpansion(
    'token',
    4611,
    refresh.normalizeRefreshOptions({
      expansionId: 4611,
      catalogBlueprintIds: [316600, 316601],
      maxProducts: 100,
      requestDelayMs: 0,
    }),
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0].expansion_id, 4611);
  assert.equal(calls[0].blueprint_id, undefined);
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].pokoinCardId, '633200');
  assert.deepEqual(result.fetchedBlueprintIds.slice().sort((a, b) => a - b), [316600, 316601]);
});

test('CardTrader blueprint pool and expansion catalog use CardTrader ids', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(
    path.join(__dirname, '_cardtrader_daily_listings_refresh.js'),
    'utf8',
  );

  assert.match(source, /select\s+ct_id as blueprint_id/);
  assert.match(source, /from public\.pokoin_pokemon_blueprints/);
  assert.match(source, /expansion_id is not null/);
});

test('seller vacation SQL freezes vanished shops instead of inferred_sale', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const vacation = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '075_seller_vacation.sql'),
    'utf8',
  );
  const persist = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '070_cardtrader_listing_qty_diff.sql'),
    'utf8',
  );
  assert.match(vacation, /cardtrader_seller_vacation/);
  assert.match(vacation, /seller_on_vacation/);
  assert.match(vacation, /seller_vanished_on_vacation/);
  assert.match(persist, /cardtrader_upsert_seller_vacation_from_refresh/);
  assert.match(persist, /cardtrader_seller_is_on_vacation/);
  assert.match(persist, /cardtrader_reclassify_vacation_vanished_sellers/);
});

test('dump-miss sanitizer restores listings still on CardTrader', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '076_sanitize_dump_miss_inferred_sales.sql'),
    'utf8',
  );
  assert.match(sql, /dump_miss/);
  assert.match(sql, /listing_still_on_cardtrader_blueprint_get/);
});

test('expansion market refresh SQL infers sold comps from cheapest-25 disappearances', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '026_cardtrader_expansion_market_refresh.sql'),
    'utf8',
  );

  assert.match(sql, /inferred_sale/);
  assert.match(sql, /dropped_from_cheapest_25/);
  assert.match(sql, /quantity_decreased/);
  assert.match(sql, /finalize_cardtrader_daily_market_refresh/);
  assert.match(sql, /p_record_ask_observations boolean default false/);
  assert.match(sql, /cardtrader_market_is_sale_reason/);
  assert.match(sql, /one_day_ready/);
  assert.match(sql, /if p_finalize and jsonb_array_length/);
  assert.match(sql, /set statement_timeout = 0/);
});

test('CardTrader snapshot upsert disables statement timeout on the same connection', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(
    path.join(__dirname, '_cardtrader_daily_listings_refresh.js'),
    'utf8',
  );

  const timeoutThenLock = source.indexOf("SET statement_timeout = 0");
  const lockCall = source.indexOf('pg_advisory_lock($1::bigint)');
  assert.ok(timeoutThenLock >= 0);
  assert.ok(lockCall > timeoutThenLock);
  assert.match(source, /SET LOCAL statement_timeout = 0/);
  assert.match(source, /queryWithDisabledStatementTimeout/);
  assert.match(source, /code === '57014'/);
});
