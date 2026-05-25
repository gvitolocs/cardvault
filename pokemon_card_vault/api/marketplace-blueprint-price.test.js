const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');
const {
  cleanBlueprintId,
  linkedCardTraderPredicate,
  parseCardTraderOfferPrice,
  pknFromUsdPrice,
  priceRow,
} = require('./marketplace-blueprint-price');

function loadEndpointWithStubs(query = async () => ({ rows: [] })) {
  const target = require.resolve('./marketplace-blueprint-price');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return { marketplaceQuery: query };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-blueprint-price');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('blueprint price accepts positive integer ids only', () => {
  assert.equal(cleanBlueprintId('274416'), '274416');
  assert.equal(cleanBlueprintId(' 274416 '), '274416');
  assert.equal(cleanBlueprintId(''), '');
  assert.equal(cleanBlueprintId('abc'), '');
  assert.equal(cleanBlueprintId('1.5'), '');
  assert.equal(cleanBlueprintId('0'), '');
});

test('blueprint price row exposes lowest active ask metadata', () => {
  assert.deepEqual(
    priceRow(
      {
        blueprint_id: 274416,
        lowest_ask_pkn: '1200.50',
        active_listing_count: 2,
        listed_quantity: 3,
        refreshed_at: '2026-05-21T08:00:00.000Z',
        source: 'cardtrader_lowest_listing',
      },
      '274416',
    ),
    {
      blueprint_id: '274416',
      card_id: '274416',
      price_pkn: 1200.5,
      currency: 'PKN',
      unit: 'PKN',
      source: 'cardtrader_lowest_listing',
      listing_count: 2,
      listed_quantity: 3,
      updated_at: '2026-05-21T08:00:00.000Z',
    },
  );
});

test('blueprint price CardTrader predicate matches linked listings', () => {
  const predicate = linkedCardTraderPredicate();
  assert.match(predicate, /lower\(coalesce\(source, ''\)\) = 'cardtrader'/);
  assert.match(predicate, /source_listing_id/);
  assert.match(predicate, /cardtrader\.com/);
});

test('blueprint price row returns null price shape without listings', () => {
  assert.deepEqual(priceRow(null, '274416'), {
    blueprint_id: '274416',
    card_id: '274416',
    price_pkn: null,
    currency: 'PKN',
    unit: 'PKN',
    source: null,
    listing_count: 0,
    listed_quantity: 0,
    updated_at: null,
  });
});

test('blueprint price parses CardTrader JSON-LD offer price', () => {
  assert.equal(
    parseCardTraderOfferPrice(
      '<script type="application/ld+json">{"@type":"Product","offers":{"@type":"Offer","priceCurrency":"USD","price":"11.46"}}</script>',
    ),
    11.46,
  );
});

test('blueprint price converts USD offers to PKN reference price', () => {
  assert.equal(pknFromUsdPrice(11.46), 2292);
});

test('blueprint price CardTrader source does not read listing cache', async (t) => {
  const captured = [];
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: true,
    text: async () =>
      '<script type="application/ld+json">{"@type":"Product","offers":{"@type":"Offer","priceCurrency":"USD","price":"11.46"}}</script>',
  });
  t.after(() => {
    global.fetch = originalFetch;
  });
  const endpoint = loadEndpointWithStubs(async (sql, values) => {
    captured.push({ sql, values });
    return { rows: [] };
  });

  const price = await endpoint.readBlueprintPrice('274416', { source: 'cardtrader' });

  assert.equal(captured.length, 0);
  assert.equal(price.price_pkn, 2292);
  assert.equal(price.source, 'cardtrader_public_offer');
});
