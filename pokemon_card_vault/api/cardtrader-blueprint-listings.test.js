const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs(query = async () => ({ rows: [] })) {
  const target = require.resolve('./cardtrader-blueprint-listings');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return { marketplaceQuery: query };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./cardtrader-blueprint-listings');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('CardTrader blueprint listings validates ids and bounds pagination', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(_test.cleanNumericId('316600'), '316600');
  assert.equal(_test.cleanNumericId('0'), '');
  assert.equal(_test.cleanNumericId('316600.5'), '');
  assert.equal(_test.cleanCardId('poke-card_123'), 'poke-card_123');
  assert.equal(_test.cleanCardId('../secret'), '');
  assert.equal(_test.cleanLimit('99999'), 250);
  assert.equal(_test.cleanLimit('0'), 1);
  assert.equal(_test.cleanPage('99999'), 1000);
});

test('CardTrader blueprint listings parses blueprintId and cardId aliases', () => {
  const { _test } = loadEndpointWithStubs();

  assert.deepEqual(
    _test.parseListingRequest(new URLSearchParams('blueprintId=316600&limit=25&page=2')),
    {
      blueprintId: '316600',
      cardId: '',
      requestedId: '316600',
      requestedParam: 'blueprintId',
      limit: 25,
      page: 2,
      cursor: '',
    },
  );
  assert.deepEqual(
    _test.parseListingRequest(new URLSearchParams('cardId=274416')),
    {
      blueprintId: '',
      cardId: '274416',
      requestedId: '274416',
      requestedParam: 'cardId',
      limit: 100,
      page: 1,
      cursor: '',
    },
  );
  assert.throws(
    () => _test.parseListingRequest(new URLSearchParams('blueprintId=abc')),
    /invalid blueprintId/,
  );
  assert.throws(
    () => _test.parseListingRequest(new URLSearchParams('')),
    /Provide blueprintId or cardId/,
  );
});

test('CardTrader blueprint listings removes sensitive raw metadata keys', () => {
  const { _test } = loadEndpointWithStubs();

  assert.deepEqual(
    _test.sanitizeMetadata({
      condition: 'Near Mint',
      api_token: 'secret',
      nested: {
        sellerName: 'Public Seller',
        email: 'hidden@example.com',
      },
    }),
    {
      condition: 'Near Mint',
      nested: {
        sellerName: 'Public Seller',
      },
    },
  );
});

test('CardTrader blueprint listings formats public snapshot rows', () => {
  const { _test } = loadEndpointWithStubs();

  assert.deepEqual(
    _test.listingRow({
      provider: 'cardtrader',
      external_listing_id: 'listing-1',
      external_product_id: 'product-1',
      blueprint_id: '316600',
      cardtrader_blueprint_id: '316600',
      pokoin_card_id: '274416',
      price: '12.50',
      price_cents: 1250,
      currency: 'EUR',
      quantity: 2,
      condition: 'Near Mint',
      language: 'en',
      properties: { foil_state: 'reverse' },
      raw_metadata: { id: 123, authorization: 'hidden' },
      seller_account_id: 'seller-1',
      seller_account_name: 'Public Seller',
      seller_country: 'IT',
      seller_type: 'professional',
      first_seen_at: '2026-05-23T10:00:00.000Z',
      last_seen_at: '2026-05-24T10:00:00.000Z',
      imported_at: '2026-05-24T10:01:00.000Z',
      updated_at: '2026-05-24T10:02:00.000Z',
    }),
    {
      externalListingId: 'listing-1',
      externalProductId: 'product-1',
      blueprintId: '316600',
      cardtraderBlueprintId: '316600',
      pokoinCardId: '274416',
      price: 12.5,
      priceCents: 1250,
      currency: 'EUR',
      quantity: 2,
      condition: 'Near Mint',
      language: 'en',
      properties: { foil_state: 'reverse' },
      rawMetadata: { id: 123 },
      seller: {
        accountId: 'seller-1',
        accountName: 'Public Seller',
        country: 'IT',
        type: 'professional',
      },
      firstSeenAt: '2026-05-23T10:00:00.000Z',
      lastSeenAt: '2026-05-24T10:00:00.000Z',
      importedAt: '2026-05-24T10:01:00.000Z',
      updatedAt: '2026-05-24T10:02:00.000Z',
      source: {
        provider: 'cardtrader',
        table: 'cardtrader_market_listing_snapshots',
      },
    },
  );
});

test('CardTrader blueprint listings reads Oracle snapshots without live token use', async () => {
  const captured = {};
  const { _test } = loadEndpointWithStubs(async (sql, values) => {
    captured.sql = sql;
    captured.values = values;
    return {
      rows: [
        {
          provider: 'cardtrader',
          external_listing_id: 'listing-1',
          external_product_id: 'product-1',
          blueprint_id: '316600',
          cardtrader_blueprint_id: '316600',
          pokoin_card_id: '274416',
          price: '12.50',
          price_cents: 1250,
          currency: 'EUR',
          quantity: 1,
          condition: 'Near Mint',
          language: 'en',
          properties: {},
          raw_metadata: {},
          seller_account_id: '',
          seller_account_name: '',
          seller_country: '',
          seller_type: '',
          first_seen_at: '2026-05-23T10:00:00.000Z',
          last_seen_at: '2026-05-24T10:00:00.000Z',
          imported_at: '2026-05-24T10:01:00.000Z',
          updated_at: '2026-05-24T10:02:00.000Z',
        },
      ],
    };
  });

  const payload = await _test.readCardTraderBlueprintListings({
    blueprintId: '316600',
    cardId: '',
    requestedId: '316600',
    requestedParam: 'blueprintId',
    limit: 100,
    page: 1,
    cursor: '',
  });

  assert.match(captured.sql, /from public\.cardtrader_market_listing_snapshots/);
  assert.doesNotMatch(captured.sql, /CARDTRADER_API_TOKEN|marketplace\/products/i);
  assert.deepEqual(captured.values, ['cardtrader', '316600', 101, 0]);
  assert.equal(payload.liveCardTraderApiUsed, false);
  assert.equal(payload.count, 1);
  assert.deepEqual(payload.mapping.cardtraderBlueprintIds, ['316600']);
  assert.deepEqual(payload.mapping.pokoinCardIds, ['274416']);
  assert.equal(payload.listings[0].externalListingId, 'listing-1');
});

test('CardTrader blueprint listings supports cursor pagination', async () => {
  const { _test } = loadEndpointWithStubs();
  const cursor = _test.encodeCursor({
    last_seen_at: '2026-05-24T10:00:00.000Z',
    external_listing_id: 'listing-1',
  });

  assert.deepEqual(_test.decodeCursor(cursor), {
    lastSeenAt: '2026-05-24T10:00:00.000Z',
    externalListingId: 'listing-1',
  });
  assert.equal(_test.decodeCursor('not-json'), null);
});
