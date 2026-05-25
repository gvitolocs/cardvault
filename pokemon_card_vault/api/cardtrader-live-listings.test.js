const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadEndpointWithStubs({
  fetchMarketplaceProducts = async () => ({}),
  marketplaceQuery = async () => ({ rows: [] }),
} = {}) {
  const target = require.resolve('./cardtrader-live-listings');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_cardtrader_client') {
      return {
        cleanToken: (value) => String(value || '').trim(),
        fetchMarketplaceProducts,
      };
    }
    if (request === './_marketplace_db') {
      return { marketplaceQuery };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./cardtrader-live-listings');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('CardTrader live listings validates ids and optional limit controls', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(_test.cleanNumericId('248856'), '248856');
  assert.equal(_test.cleanNumericId('0'), '');
  assert.equal(_test.cleanNumericId('248856.5'), '');
  assert.equal(_test.cleanCardId('poke-card_123'), 'poke-card_123');
  assert.equal(_test.cleanCardId('../secret'), '');
  assert.equal(_test.cleanLanguage('en'), 'en');
  assert.equal(_test.cleanLanguage('../en'), '');
  assert.equal(_test.cleanLimit(''), null);
  assert.equal(_test.cleanLimit('999'), 999);
  assert.equal(_test.cleanLimit('5000'), _test.MAX_EXPLICIT_LIMIT);
  assert.equal(_test.configuredCardTraderApiToken({ CARDTRADER_AUTH_TOKEN: ' auth-token ' }), 'auth-token');
  assert.equal(
    _test.configuredCardTraderApiToken({
      CARDTRADER_AUTH_TOKEN: ' primary-token ',
      CARDTRADER_API_TOKEN: ' old-token ',
    }),
    'primary-token',
  );
});

test('CardTrader live listings parses blueprintId and cardId aliases', () => {
  const { _test } = loadEndpointWithStubs();

  assert.deepEqual(
    _test.parseLiveListingsRequest(new URLSearchParams('blueprintId=316600&language=en&limit=10')),
    {
      blueprintId: '316600',
      cardId: '',
      requestedId: '316600',
      requestedParam: 'blueprintId',
      language: 'en',
      limit: 10,
    },
  );
  assert.deepEqual(
    _test.parseLiveListingsRequest(new URLSearchParams('cardId=248856')),
    {
      blueprintId: '',
      cardId: '248856',
      requestedId: '248856',
      requestedParam: 'cardId',
      language: '',
      limit: null,
    },
  );
  assert.throws(
    () => _test.parseLiveListingsRequest(new URLSearchParams('blueprintId=abc')),
    /invalid blueprintId/,
  );
  assert.throws(
    () => _test.parseLiveListingsRequest(new URLSearchParams('')),
    /Provide blueprintId or cardId/,
  );
});

test('CardTrader live listings returns all rows by default and caps explicit limits only', () => {
  const { _test } = loadEndpointWithStubs();
  const products = Array.from({ length: 30 }, (_, index) => ({
    id: index + 1,
    blueprint_id: 248856,
    quantity: 1,
    price: { cents: 100 + index, currency: 'EUR' },
    user: { can_sell_via_hub: true },
  }));

  const defaultListings = _test.listingsFromMarketplacePayload({ 248856: products }, '248856');
  const cappedListings = _test.listingsFromMarketplacePayload({ 248856: products }, '248856', 10);

  assert.equal(defaultListings.length, 30);
  assert.equal(defaultListings.at(-1).externalListingId, '30');
  assert.equal(cappedListings.length, 10);
  assert.equal(cappedListings.at(-1).externalListingId, '10');
});

test('CardTrader live listings normalizes marketplace products without secrets', () => {
  const { _test } = loadEndpointWithStubs();
  const listing = _test.normalizeLiveListing({
    id: 123,
    blueprint_id: 316600,
    name_en: 'Pikachu',
    quantity: 2,
    description: 'Public note',
    seller_comment: 'Tiny edge whitening',
    price: {
      cents: 1299,
      currency: 'EUR',
    },
    buyer_price: {
      cents: 1399,
      currency: 'EUR',
    },
    seller_price: {
      cents: 1200,
      currency: 'EUR',
    },
    formatted_price: '€12.99',
    properties_hash: {
      condition: 'Near Mint',
      language: 'English',
      pokemon_reverse: true,
      api_token: 'hidden',
    },
    expansion: {
      id: 99,
      code: 'SV',
      name_en: 'Scarlet & Violet',
    },
    user: {
      id: 456,
      username: 'Seller One',
      country_code: 'IT',
      user_type: 'professional',
      can_sell_via_hub: true,
      can_sell_sealed_with_ct_zero: true,
      max_sellable_in24h_quantity: 7,
      email: 'hidden@example.com',
    },
    authorization: 'hidden',
    graded: false,
    on_vacation: false,
    bundle_size: 1,
  });

  assert.equal(listing.externalListingId, '123');
  assert.equal(listing.cardtraderProductId, '123');
  assert.equal(listing.cardtraderBlueprintId, '316600');
  assert.equal(listing.price, 12.99);
  assert.equal(listing.priceCents, 1299);
  assert.equal(listing.currency, 'EUR');
  assert.equal(listing.displayPricePkn, 2798);
  assert.equal(listing.markupPkn, 200);
  assert.equal(listing.buyerPrice.priceCents, 1399);
  assert.equal(listing.sellerPrice.priceCents, 1200);
  assert.equal(listing.quantity, 2);
  assert.equal(listing.condition, 'NM');
  assert.equal(listing.sellerComment, 'Tiny edge whitening');
  assert.equal(listing.language, 'en');
  assert.equal(listing.expansion.name, 'Scarlet & Violet');
  assert.equal(listing.seller.accountName, 'pknreserve');
  assert.equal(listing.seller.sourceAccountName, 'Seller One');
  assert.equal(listing.seller.canSellViaHub, true);
  assert.equal(listing.seller.canSellSealedWithCtZero, true);
  assert.equal(listing.seller.maxSellableIn24hQuantity, 7);
  assert.equal(listing.shippingMode, 'zero');
  assert.equal(listing.shippingLabel, 'Zero');
  assert.equal(listing.properties.api_token, undefined);
  assert.equal(listing.rawMetadata.authorization, undefined);
  assert.equal(listing.rawMetadata.user.email, undefined);
  assert.equal(listing.source.live, true);
  assert.equal(listing.source.persisted, false);
});

test('CardTrader live listings extracts public seller comments and normalizes conditions', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(_test.publicSellerComment({
    description: 'from booster to sleeve + toploader, fast shipping',
  }), 'from booster to sleeve + toploader, fast shipping');
  assert.equal(_test.publicSellerComment({
    description: 'CardTrader Zero',
    properties_hash: { seller_comment: 'Do not expose property metadata as seller text' },
  }), '');
  assert.equal(_test.publicSellerComment({
    seller_comment: 'Tiny edge whitening',
    description: 'CardTrader Zero',
  }), 'Tiny edge whitening');
  assert.equal(_test.publicSellerComment({
    seller_comment: 'Check my store, more cards available! :3',
  }), '');
  assert.equal(_test.publicSellerComment({
    description: 'Please check photos for corner wear',
  }), 'Please check photos for corner wear');
  assert.equal(_test.normalizeCondition('Near Mint'), 'NM');
  assert.equal(_test.normalizeCondition('Lightly Played'), 'SP');
  assert.equal(_test.normalizeCondition('GD'), 'MP');
  assert.equal(_test.normalizeCondition('PO'), 'Poor');
});

test('CardTrader live listings filters to zero or 1-Day Ready and converts EUR plus markup to PKN', () => {
  const { _test } = loadEndpointWithStubs();

  assert.equal(_test.pknReferencePrice({ PKN_CHECKOUT_USDT_PRICE: '0.01' }), 0.01);
  assert.equal(_test.cardTraderDisplayPricePkn(4, 'EUR', { PKN_CHECKOUT_USDT_PRICE: '0.01' }), 600);

  const listings = _test.listingsFromMarketplacePayload(
    {
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
      ],
    },
    '316600',
  );

  assert.deepEqual(listings.map((listing) => listing.externalListingId), ['1', '2']);
  assert.deepEqual(listings.map((listing) => listing.seller.accountName), ['pknreserve', 'pknreserve']);
  assert.equal(listings[0].displayPricePkn, 1000);
  assert.equal(_test.CARDTRADER_MARKUP_PKN, 200);
});

test('CardTrader live listings infers shipping mode for blueprint 248856 examples', () => {
  const { _test } = loadEndpointWithStubs();
  const listings = _test.listingsFromMarketplacePayload(
    {
      248856: [
        {
          id: 375795370,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'PL',
          price: { cents: 23900, currency: 'EUR' },
          user: {
            username: 'EeveeRaff 1-Day Ready',
            max_sellable_in24h_quantity: 1,
            can_sell_via_hub: true,
          },
        },
        {
          id: 332412221,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'GD',
          price: { cents: 37900, currency: 'EUR' },
          user: {
            username: 'Mikebarocco',
            display_name: '1-Day Ready',
            max_sellable_in24h_quantity: 1,
            can_sell_via_hub: true,
          },
        },
        {
          id: 414080138,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'PO',
          price: { cents: 7064, currency: 'EUR' },
          user: {
            username: 'Lolimpodelnerd',
            display_name: '3.5K PRO',
            can_sell_via_hub: true,
            can_sell_sealed_with_ct_zero: true,
            max_sellable_in24h_quantity: 0,
          },
        },
        {
          id: 404023065,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'PO',
          price: { cents: 9000, currency: 'EUR' },
          user: {
            username: 'Laconteacag',
            display_name: '22K PRO',
            can_sell_via_hub: true,
            can_sell_sealed_with_ct_zero: false,
            max_sellable_in24h_quantity: 1,
          },
        },
        {
          id: 385562055,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'PO',
          price: { cents: 11000, currency: 'EUR' },
          user: {
            username: 'Card Universe',
            display_name: '28K PRO',
            can_sell_via_hub: true,
            can_sell_sealed_with_ct_zero: true,
            max_sellable_in24h_quantity: 5,
          },
        },
        {
          id: 402300433,
          blueprint_id: 248856,
          quantity: 1,
          condition: 'NM',
          price: { cents: 16864, currency: 'EUR' },
          user: {
            username: 'Tcg-mapro54_cardsita',
            display_name: '7',
            user_type: 'professional',
            can_sell_via_hub: false,
            can_sell_sealed_with_ct_zero: false,
            max_sellable_in24h_quantity: 0,
          },
        },
      ],
    },
    '248856',
    25,
  );

  assert.deepEqual(
    listings.map((listing) => ({
      id: listing.externalListingId,
      mode: listing.shippingMode,
      label: listing.shippingLabel,
    })),
    [
      { id: '375795370', mode: 'one_day_ready', label: '1-Day Ready' },
      { id: '332412221', mode: 'one_day_ready', label: '1-Day Ready' },
      { id: '414080138', mode: 'zero', label: 'Zero' },
      { id: '404023065', mode: 'zero', label: 'Zero' },
      { id: '385562055', mode: 'zero', label: 'Zero' },
    ],
  );
});

test('CardTrader live listings calls marketplace products by direct blueprint id', async () => {
  const captured = {};
  const { _test } = loadEndpointWithStubs({
    fetchMarketplaceProducts: async (token, params) => {
      captured.token = token;
      captured.params = params;
      return {
        316600: [
          {
            id: 1,
            blueprint_id: 316600,
            quantity: 1,
            price: { cents: 500, currency: 'USD' },
            user: { can_sell_via_hub: true },
          },
        ],
      };
    },
    marketplaceQuery: async () => {
      throw new Error('direct blueprint lookup must not query Oracle');
    },
  });

  _test.clearLiveListingsCache();
  const payload = await _test.readLiveCardTraderListings(
    {
      blueprintId: '316600',
      cardId: '',
      requestedId: '316600',
      requestedParam: 'blueprintId',
      language: 'en',
      limit: null,
    },
    { env: { CARDTRADER_API_TOKEN: 'global-token' }, now: () => Date.parse('2026-05-24T09:00:00.000Z') },
  );

  assert.equal(captured.token, 'global-token');
  assert.deepEqual(captured.params, { blueprint_id: '316600', language: 'en' });
  assert.equal(payload.liveCardTraderApiUsed, true);
  assert.equal(payload.persisted, false);
  assert.equal(payload.mapping.source, 'direct_cardtrader_blueprint_id');
  assert.equal(payload.count, 1);
  assert.equal(payload.listings[0].externalListingId, '1');
  assert.equal(payload.requested.limit, null);
  assert.deepEqual(payload.pagination, { limit: null, limited: false, returned: 1 });
  assert.equal(payload.cache.hit, false);
});

test('CardTrader live listings resolves numeric cardId through Oracle mapping only for ids', async () => {
  const captured = {};
  const { _test } = loadEndpointWithStubs({
    fetchMarketplaceProducts: async (token, params) => {
      captured.params = params;
      return {
        248856: [
          {
            id: 2,
            quantity: 1,
            price_cents: 700,
            currency: 'EUR',
            user: { can_sell_via_hub: true },
          },
        ],
      };
    },
    marketplaceQuery: async (sql, values) => {
      captured.sql = sql;
      captured.values = values;
      return {
        rows: [
          {
            pokoin_card_id: '248856',
            cardtrader_blueprint_id: '248856',
          },
        ],
      };
    },
  });

  _test.clearLiveListingsCache();
  const payload = await _test.readLiveCardTraderListings(
    {
      blueprintId: '',
      cardId: '248856',
      requestedId: '248856',
      requestedParam: 'cardId',
      language: '',
      limit: null,
    },
    { env: { CARDTRADER_AUTH_TOKEN: 'global-token' }, now: () => Date.parse('2026-05-24T09:01:00.000Z') },
  );

  assert.match(captured.sql, /from \(select \$1::bigint as requested_id\) input/);
  assert.doesNotMatch(captured.sql, /insert|update|delete|refresh_cardtrader_market_listing_snapshots/i);
  assert.deepEqual(captured.values, ['248856']);
  assert.deepEqual(captured.params, { blueprint_id: '248856' });
  assert.equal(payload.requested.param, 'cardId');
  assert.equal(payload.mapping.cardtraderBlueprintId, '248856');
  assert.equal(payload.mapping.pokoinCardId, '248856');
  assert.equal(payload.mapping.source, 'oracle_card_data');
  assert.equal(payload.count, 1);
});

test('CardTrader live listings caches repeated live calls briefly', async () => {
  let fetchCount = 0;
  const { _test } = loadEndpointWithStubs({
    fetchMarketplaceProducts: async () => {
      fetchCount += 1;
      return {
        316600: [
          {
            id: 3,
            quantity: 1,
            price_cents: 900,
            currency: 'EUR',
            user: { can_sell_via_hub: true },
          },
        ],
      };
    },
  });
  const request = {
    blueprintId: '316600',
    cardId: '',
    requestedId: '316600',
    requestedParam: 'blueprintId',
    language: '',
    limit: null,
  };

  _test.clearLiveListingsCache();
  const first = await _test.readLiveCardTraderListings(
    request,
    { env: { CARDTRADER_API_TOKEN: 'global-token' }, now: () => Date.parse('2026-05-24T09:02:00.000Z') },
  );
  const second = await _test.readLiveCardTraderListings(
    request,
    { env: { CARDTRADER_API_TOKEN: 'global-token' }, now: () => Date.parse('2026-05-24T09:02:10.000Z') },
  );

  assert.equal(fetchCount, 1);
  assert.equal(first.cache.hit, false);
  assert.equal(second.cache.hit, true);
  assert.equal(second.count, 1);
});
