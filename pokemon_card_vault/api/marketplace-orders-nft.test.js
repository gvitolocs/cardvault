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
      return {
        _test: {
          readLiveCardTraderListings: async () => ({ listings: [] }),
        },
      };
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

test('marketplace orders normalizes NFT fulfillment fields', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const item = _test.normalizeItem({
    card: { id: 'card-1', name: 'Pikachu' },
    listingId: 'listing-1',
    sellerUid: 'seller-1',
    quantity: 1,
    unitPricePkn: 100,
    reserveAvailable: true,
    nftAvailable: true,
    fulfillmentMode: 'nft_only',
  });

  assert.equal(item.reserveAvailable, true);
  assert.equal(item.nftAvailable, true);
  assert.equal(item.fulfillmentMode, 'nft_only');
});

test('marketplace orders builds NFT collection payload', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const payload = _test.collectionPayloadForItem({
    uid: 'buyer-uid',
    orderId: 'order-123',
    now: 'SERVER_TIME',
    item: _test.normalizeItem({
      card: {
        id: 'card-1',
        name: 'Pikachu',
        imageUrl: 'https://cdn.pokoin.com/pikachu.png',
        set: 'Base',
        number: '58/102',
      },
      listingId: 'listing-1',
      sellerUid: 'seller-1',
      quantity: 2,
      unitPricePkn: 100,
      condition: 'NM',
      language: 'EN',
      nftAvailable: true,
    }),
  });

  assert.equal(payload.uid, 'buyer-uid');
  assert.equal(payload.ownershipType, 'nft');
  assert.equal(payload.fulfillmentMode, 'nft_only');
  assert.equal(payload.physicalShippingStatus, 'not_requested');
  assert.equal(payload.sourceOrderId, 'order-123');
  assert.equal(payload.cardName, 'Pikachu');
});

test('marketplace orders sanitizes shipping address payloads', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  assert.deepEqual(_test.shippingAddressFromBody({
    name: ' Ash ',
    line1: 'Pallet Town',
    postal_code: '001',
    city: 'Kanto',
    country: 'JP',
    ignored: 'nope',
  }), {
    name: 'Ash',
    line1: 'Pallet Town',
    line2: '',
    city: 'Kanto',
    region: '',
    postalCode: '001',
    country: 'JP',
    phone: '',
  });
});
