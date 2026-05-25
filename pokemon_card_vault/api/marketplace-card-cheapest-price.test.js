const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cardIdFromCanonicalPath,
  cheapestPriceRow,
  cleanLookupCardIds,
  createHandler,
  readCheapestPrices,
} = require('./marketplace-card-cheapest-price')._test;
const { resetCheapestHomepageCacheRelationForTest } = require('./marketplace-cards');

test.afterEach(() => {
  resetCheapestHomepageCacheRelationForTest();
});

test('cheapest price lookup accepts card ids and canonical marketplace paths', () => {
  assert.deepEqual(
    cleanLookupCardIds({
      cardId: '274416',
      blueprintId: '274417',
      cardIds: '316600, not-a-card, 497712',
      canonicalPath:
        '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
    }),
    ['274416', '274417', '316600', '497712'],
  );
  assert.equal(
    cardIdFromCanonicalPath(
      'https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates?utm=extension',
    ),
    '274416',
  );
});

test('cheapest price row mirrors homepage CardTrader cache priority', () => {
  const row = cheapestPriceRow({
    card_id: 274416,
    canonical_path: '/marketplace/en/cards/548832/mew-ex',
    public_number: '548832',
    language: 'en',
    name: 'Mew ex',
    set_name: 'Paldean Fates',
    card_number: '232/091',
    native_lowest_ask_pkn: '1200',
    native_active_listing_count: 2,
    native_listed_quantity: 3,
    native_refreshed_at: '2026-05-21T08:00:00.000Z',
    cardtrader_lowest_price_pkn: '800',
    cardtrader_lowest_price_eur: '4',
    cardtrader_eligible_listing_count: 1,
    cardtrader_listed_quantity: 2,
    cardtrader_sample_listing_id: 'ct-listing-1',
    cardtrader_sample_product_id: 'ct-product-1',
    cardtrader_updated_at: '2026-05-21T09:00:00.000Z',
  });

  assert.equal(row.cardId, '274416');
  assert.equal(row.price, 800);
  assert.equal(row.pricePkn, 800);
  assert.equal(row.priceUsdt, 4);
  assert.equal(row.source, 'cardtrader_homepage_cache');
  assert.equal(row.listingId, 'ct-listing-1');
  assert.equal(row.listingCount, 1);
  assert.equal(row.listedQuantity, 2);
  assert.equal(row.available, true);
  assert.equal(row.inStock, true);
  assert.equal(row.cardtrader.source, 'cheapest_homepage_cache_blueprint');
  assert.equal(row.nativeListing.source, 'marketplace_blueprint_price_summary');
});

test('cheapest price row falls back to native summary when cache is empty', () => {
  const row = cheapestPriceRow({
    card_id: 316600,
    native_lowest_ask_pkn: '950',
    native_active_listing_count: 3,
    native_listed_quantity: 4,
    native_refreshed_at: '2026-05-21T08:00:00.000Z',
  });

  assert.equal(row.price, 950);
  assert.equal(row.source, 'marketplace_blueprint_price_summary');
  assert.equal(row.listingCount, 3);
  assert.equal(row.listedQuantity, 4);
  assert.equal(row.cardtrader.available, false);
});

test('readCheapestPrices uses homepage cache relation and structured lookup fields', async () => {
  resetCheapestHomepageCacheRelationForTest();
  const calls = [];
  const prices = await readCheapestPrices({
    name: 'Mew ex',
    setName: 'Paldean Fates',
    collectorNumber: '232/091',
    language: 'en',
  }, async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql.includes('to_regclass')) {
      return { rows: [{ relation: 'public.cheapest_homepage_cache_blueprint' }] };
    }
    assert.match(sql, /public\.marketplace_blueprint_price_summary/);
    assert.match(sql, /public\.cheapest_homepage_cache_blueprint/);
    assert.match(sql, /public\.marketplace_search_compact\(c\.name\)/);
    assert.deepEqual(values.slice(0, 5), [
      [],
      'Mew ex',
      'Paldean Fates',
      '232/091',
      'en',
    ]);
    return {
      rows: [{
        card_id: 274416,
        name: 'Mew ex',
        set_name: 'Paldean Fates',
        card_number: '232/091',
        canonical_path:
          '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
        public_number: '548832',
        language: 'en',
        cardtrader_lowest_price_pkn: 800,
        cardtrader_eligible_listing_count: 1,
        cardtrader_listed_quantity: 1,
      }],
    };
  });

  assert.equal(calls.length, 2);
  assert.equal(prices.length, 1);
  assert.equal(prices[0].cardId, '274416');
  assert.equal(prices[0].source, 'cardtrader_homepage_cache');
});

test('cheapest price handler is CORS-enabled and extension-friendly', async () => {
  resetCheapestHomepageCacheRelationForTest();
  const headers = {};
  const handler = createHandler({
    query: async (sql) => {
      if (sql.includes('to_regclass')) {
        return { rows: [{ relation: 'public.cheapest_homepage_cache_blueprint' }] };
      }
      return {
        rows: [{
          card_id: 274416,
          canonical_path: '/marketplace/en/cards/548832/mew-ex',
          public_number: '548832',
          language: 'en',
          name: 'Mew ex',
          set_name: 'Paldean Fates',
          card_number: '232/091',
          cardtrader_lowest_price_pkn: 800,
          cardtrader_eligible_listing_count: 1,
          cardtrader_listed_quantity: 1,
        }],
      };
    },
  });
  const res = {
    setHeader(name, value) {
      headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    end() {
      this.ended = true;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };

  await handler({
    method: 'GET',
    url: '/api/marketplace-card-cheapest-price?canonicalPath=%2Fmarketplace%2Fen%2Fcards%2F548832%2Fmew-ex',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.price.cardId, '274416');
  assert.equal(res.body.price.pricePkn, 800);
  assert.equal(res.body.count, 1);
  assert.equal(headers['access-control-allow-origin'], '*');
  assert.match(headers['cache-control'], /s-maxage=30/);
});
