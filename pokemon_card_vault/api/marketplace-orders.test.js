const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadMarketplaceOrdersWithStubs() {
  const target = require.resolve('./marketplace-orders');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_firebase') {
      return {
        getFirebaseAdmin: () => ({}),
        verifyBearerToken: async () => ({ uid: 'buyer-uid' }),
      };
    }
    if (request === './_marketplace_db') {
      return { marketplaceQuery: async () => ({ rows: [] }) };
    }
    if (request === './_marketplace_sale_notifications') {
      return { sendSellerSaleNotificationsForPaidOrder: async () => ({ ok: true }) };
    }
    if (request === './_cardtrader_client') {
      return {
        addProductToCart: async () => ({}),
        fetchCart: async () => ({}),
        purchaseCart: async () => ({}),
      };
    }
    if (request === './cardtrader-live-listings') {
      return { _test: { readLiveCardTraderListings: async () => ({ listings: [] }) } };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-orders');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function cardTraderItem(overrides = {}) {
  return {
    card: { id: '316600', name: 'Leafeon' },
    listingId: 'cardtrader:live:123',
    sellerUid: 'reserve-uid',
    quantity: 1,
    unitPricePkn: 1000,
    totalPricePkn: 1000,
    source: 'cardtrader_live',
    sourceListingId: 'cardtrader:live:123',
    sourceMetadata: {
      cardtraderProductId: '123',
      cardtraderBlueprintId: '316600',
      shippingMode: 'zero',
    },
    ...overrides,
  };
}

test('CardTrader buy token prefers CARDTRADER_AUTH_TOKEN and still needs live flag', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();

  assert.equal(_test.configuredCardTraderBuyToken({
    CARDTRADER_AUTH_TOKEN: 'auth-token',
    CARDTRADER_API_TOKEN: 'api-token',
  }), 'auth-token');
  assert.throws(
    () => _test.assertCardTraderBuyConfigured({ CARDTRADER_AUTH_TOKEN: 'auth-token' }),
    /CardTrader live buying is disabled/,
  );
  assert.equal(
    _test.assertCardTraderBuyConfigured({
      CARDTRADER_AUTH_TOKEN: 'auth-token',
      CARDTRADER_BUY_ENABLED: 'true',
    }),
    'auth-token',
  );
});

test('CardTrader checkout fails closed unless enabled, except NFT-only custody', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const item = cardTraderItem();

  assert.throws(
    () => _test.assertCardTraderCheckoutCanProceed([item], {}, { CARDTRADER_AUTH_TOKEN: 'auth-token' }),
    /CardTrader live buying is disabled/,
  );
  assert.doesNotThrow(() => _test.assertCardTraderCheckoutCanProceed(
    [item],
    { fulfillmentMode: 'nft_only' },
    { CARDTRADER_AUTH_TOKEN: 'auth-token' },
  ));
});

test('CardTrader cart guard blocks non-empty cart before purchase', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs();

  await assert.rejects(
    () => _test.assertCardTraderCartIsEmpty('token', { getCart: async () => ({ items: [{ product: { id: 1 } }] }) }),
    /cart is not empty/,
  );
  await assert.doesNotReject(
    () => _test.assertCardTraderCartIsEmpty('token', { getCart: async () => ({ items: [] }) }),
  );
});
