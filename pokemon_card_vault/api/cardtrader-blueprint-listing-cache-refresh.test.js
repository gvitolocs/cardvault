const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadRefreshModuleWithStubs(stubs = {}) {
  const target = require.resolve('./_cardtrader_blueprint_listing_cache_refresh');
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
      return { marketplaceQuery: stubs.marketplaceQuery || (async () => ({ rows: [] })) };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./_cardtrader_blueprint_listing_cache_refresh');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('CardTrader listing cache refresh options default to card scope and safe batching', () => {
  const refresh = loadRefreshModuleWithStubs();
  const options = refresh.normalizeCacheRefreshOptions({
    maxBlueprints: 500,
    refreshBatchBlueprints: 700,
    blueprintConcurrency: 99,
    requestDelayMs: 250,
    productType: 'card',
    blueprintIds: '316600,316601',
  });

  assert.equal(options.maxBlueprints, 500);
  assert.equal(options.refreshBatchBlueprints, 700);
  assert.equal(options.blueprintConcurrency, 20);
  assert.equal(options.requestDelayMs, 250);
  assert.equal(options.productType, 'card');
  assert.deepEqual(options.blueprintIds, [316600, 316601]);
});

test('CardTrader listing cache refresh reads homepage card candidates first', async () => {
  const calls = [];
  const refresh = loadRefreshModuleWithStubs();
  await refresh.readBlueprintIdsFromCandidates(25, { productType: 'card' }, async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [{ blueprint_id: '316600' }] };
  });

  assert.match(calls[0].sql, /from public\.marketplace_search_candidates/);
  assert.match(calls[0].sql, /item_kind = 'single'/);
  assert.match(calls[0].sql, /product_type = 'card'/);
  assert.match(calls[0].sql, /search_weight desc/);
  assert.deepEqual(calls[0].values, [25]);
});

test('CardTrader listing cache product scope avoids unrelated product categories', async () => {
  const calls = [];
  const refresh = loadRefreshModuleWithStubs();
  await refresh.readBlueprintIdsFromCandidates(25, { productType: 'product' }, async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [] };
  });

  assert.match(calls[0].sql, /item_kind = 'product'/);
  assert.match(calls[0].sql, /product_type = any/);
  assert.ok(calls[0].values[1].includes('booster_pack'));
  assert.equal(calls[0].values[1].includes('accessory'), false);
});

test('CardTrader listing cache filters true Zero flags and explicit 1-Day Ready', () => {
  const refresh = loadRefreshModuleWithStubs();
  const rows = refresh.cacheRowsFromMarketplacePayload({
    316600: [
      {
        id: 1,
        blueprint_id: 316600,
        quantity: 1,
        price: { cents: 400, currency: 'EUR' },
        user: { display_name: '1-Day Ready' },
      },
      {
        id: 2,
        blueprint_id: 316600,
        quantity: 1,
        price: { cents: 500, currency: 'EUR' },
        user: { can_sell_via_hub: true },
      },
      {
        id: 3,
        blueprint_id: 316600,
        quantity: 1,
        price: { cents: 600, currency: 'EUR' },
        user: { can_sell_via_hub: false },
      },
      {
        id: 4,
        blueprint_id: 316600,
        quantity: 1,
        price: { cents: 700, currency: 'EUR' },
        can_sell_sealed_with_ct_zero: 'yes',
      },
    ],
  });

  assert.deepEqual(rows.map((row) => row.externalListingId), ['1', '2', '4']);
  assert.deepEqual(rows.map((row) => row.shippingMode), ['one_day_ready', 'zero', 'zero']);
});

test('CardTrader listing cache computes PKN with existing +200 markup', () => {
  const refresh = loadRefreshModuleWithStubs();
  assert.equal(
    refresh.marketplacePricePknFromCardTrader(4, null, 'EUR', { PKN_CHECKOUT_USDT_PRICE: '0.01' }) +
      refresh.CARDTRADER_MARKUP_PKN,
    600,
  );
});

test('CardTrader listing cache upsert writes cache only and clears scoped misses', async () => {
  const refresh = loadRefreshModuleWithStubs();
  const calls = [];
  const result = await refresh.refreshOracleBlueprintListingCache({
    rows: [],
    scopeBlueprintIds: [316600],
    env: { PKN_CHECKOUT_USDT_PRICE: '0.005' },
    query: async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [{
          scoped_count: 1,
          incoming_count: 0,
          eligible_listing_count: 0,
          eligible_blueprint_count: 0,
          upserted_count: 0,
          deleted_count: 1,
        }],
      };
    },
  });

  assert.equal(result.deletedCount, 1);
  assert.match(calls[0].sql, /insert into public\.cardtrader_blueprint_listing_cache/);
  assert.match(calls[0].sql, /delete from public\.cardtrader_blueprint_listing_cache/);
  assert.doesNotMatch(calls[0].sql, /insert into public\.cardtrader_market_listing_snapshots/);
  assert.doesNotMatch(calls[0].sql, /refresh_cardtrader_market_listing_snapshots/);
  assert.deepEqual(calls[0].values[1], [316600]);
});

test('CardTrader listing cache script parses refresh flags', () => {
  const script = require('../scripts/refresh-cardtrader-blueprint-listing-cache');
  const options = script.parseArgs([
    '--env-file=/tmp/peer4.env',
    '--dry-run',
    '--max-blueprints=25',
    '--refresh-batch-blueprints=700',
    '--blueprint-concurrency=2',
    '--request-delay-ms=1000',
    '--product-type=card',
    '--blueprint-id=316600',
    '--blueprint-ids=316601,316602',
  ]);

  assert.equal(options.envFile, '/tmp/peer4.env');
  assert.equal(options.dryRun, true);
  assert.equal(options.maxBlueprints, 25);
  assert.equal(options.refreshBatchBlueprints, 700);
  assert.equal(options.blueprintConcurrency, 2);
  assert.equal(options.requestDelayMs, 1000);
  assert.equal(options.productType, 'card');
  assert.deepEqual(options.blueprintIds, [316600, 316601, 316602]);
});
