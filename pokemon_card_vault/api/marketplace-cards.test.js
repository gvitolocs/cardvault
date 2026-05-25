const assert = require('node:assert/strict');
const test = require('node:test');

const {
  availabilityColumns,
  cardTraderAvailabilityJoin,
  cardTraderEligiblePredicate,
  cheapestHomepageCacheRelationName,
  productFacetRows,
  resetCheapestHomepageCacheRelationForTest,
} = require('./marketplace-cards');
const {
  watchlistAnalyticsJoin,
  watchlistCountColumn,
} = require('./_marketplace_watchlist_analytics');
const {
  cartAnalyticsJoin,
  cartHolderCountColumn,
} = require('./_marketplace_cart_analytics');

test('marketplace cards CardTrader availability SQL exposes tile availability', () => {
  const joinSql = cardTraderAvailabilityJoin('candidate');
  const columnsSql = availabilityColumns('price_summary', 'cardtrader');

  assert.match(joinSql, /public\.cheapest_homepage_cache_blueprint/);
  assert.match(joinSql, /left join lateral/);
  assert.match(joinSql, /cardtrader_cache\.blueprint_id = candidate\.card_id/);
  assert.match(joinSql, /cardtrader_cache\.pokoin_card_id = candidate\.card_id::text/);
  assert.match(joinSql, /cardtrader_cache\.eligible_listing_count > 0/);
  assert.match(joinSql, /cardtrader_cache\.cheapest_price_pkn is not null/);
  assert.match(joinSql, /order by[\s\S]*cardtrader_cache\.cheapest_price_pkn asc/);
  assert.match(columnsSql, /cardtrader_eligible_listing_count/);
  assert.match(columnsSql, /has_cardtrader_listing/);
  assert.match(columnsSql, /when cardtrader\.cheapest_price_pkn is not null then cardtrader\.cheapest_price_pkn/);
  assert.doesNotMatch(joinSql, /cardtrader_market_listing_snapshots/);
});

test('marketplace cards can read old cheapest cache table during rollout', () => {
  const joinSql = cardTraderAvailabilityJoin(
    'candidate',
    'public.cardtrader_blueprint_listing_cache',
  );

  assert.match(joinSql, /public\.cardtrader_blueprint_listing_cache/);
  assert.match(joinSql, /cardtrader_cache\.blueprint_id = candidate\.card_id/);
});

test('marketplace cards resolves canonical cheapest homepage cache relation', async () => {
  resetCheapestHomepageCacheRelationForTest();
  const relation = await cheapestHomepageCacheRelationName(async () => ({
    rows: [{ relation: 'public.cardtrader_blueprint_listing_cache' }],
  }));

  assert.equal(relation, 'public.cardtrader_blueprint_listing_cache');
  resetCheapestHomepageCacheRelationForTest();
});

test('marketplace cards CardTrader availability SQL filters CardTrader Zero only', () => {
  const predicate = cardTraderEligiblePredicate('snapshot');

  assert.match(predicate, /can_sell_via_hub/);
  assert.match(predicate, /can_sell_sealed_with_ct_zero/);
  assert.doesNotMatch(predicate, /day/);
  assert.doesNotMatch(predicate, /ready/);
  assert.match(predicate, /quantity, 0\) > 0/);
});

test('marketplace cards exposes independent watchlist analytics join', () => {
  const joinSql = watchlistAnalyticsJoin('candidate');
  const columnsSql = watchlistCountColumn();

  assert.match(joinSql, /public\.marketplace_card_watchlist_analytics/);
  assert.match(joinSql, /watchlist_analytics\.blueprint_id = candidate\.card_id/);
  assert.match(columnsSql, /coalesce\(watchlist_analytics\.watchlist_count, 0\) as watchlist_count/);
  assert.doesNotMatch(joinSql, /cardtrader/);
});

test('marketplace cards exposes independent cart holder analytics join', () => {
  const joinSql = cartAnalyticsJoin('candidate');
  const columnsSql = cartHolderCountColumn();

  assert.match(joinSql, /public\.marketplace_card_cart_analytics/);
  assert.match(joinSql, /cart_analytics\.blueprint_id = candidate\.card_id/);
  assert.match(columnsSql, /coalesce\(cart_analytics\.cart_holder_count, 0\) as cart_holder_count/);
  assert.doesNotMatch(joinSql, /cardtrader/);
});

test('marketplace cards product facets group singles and product types', async () => {
  let capturedSql = '';
  const rows = [
    { product_type: 'card', count: 12 },
    { product_type: 'booster_pack', count: 3 },
  ];

  const facets = await productFacetRows({
    query: '151',
    searchLanguage: 'en',
    dbQuery: async (sql) => {
      capturedSql = sql;
      return { rows };
    },
  });

  assert.deepEqual(facets, [
    { productType: 'card', count: 12 },
    { productType: 'booster_pack', count: 3 },
  ]);
  assert.match(capturedSql, /item_kind = 'product'/);
  assert.match(capturedSql, /coalesce\(nullif\(marketplace_search_candidates\.product_type, ''\), 'sealed_product'\)/);
  assert.match(capturedSql, /group by 1/);
  assert.match(capturedSql, /marketplace_search_candidates\.name ilike/);
});
