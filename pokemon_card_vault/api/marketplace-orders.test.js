const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadMarketplaceOrdersWithStubs({ query = async () => ({ rows: [] }), liveListings = async () => ({ listings: [] }) } = {}) {
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
      return {
        marketplaceQuery: (...args) => query(...args),
        marketplaceWriteQuery: (...args) => query(...args),
      };
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
      return { _test: { PKNRESERVE_SELLER_USERNAME: 'pknreserve', readLiveCardTraderListings: (...args) => liveListings(...args) } };
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

test('physical checkout uses escrow; NFT-only does not', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  assert.equal(_test.physicalUsesEscrow('physical'), true);
  assert.equal(_test.physicalUsesEscrow('nft_only'), false);
});

test('not-shipped refund waits 7 days and only while PKN is still in escrow', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const now = Date.parse('2026-09-17T00:00:00.000Z');
  assert.equal(_test.canAutoRefundNotShipped({
    paymentStatus: 'escrow',
    fulfillmentStatus: 'awaiting_shipment',
    createdAt: '2026-09-10T00:00:00.000Z',
  }, now), true);
  assert.equal(_test.canAutoRefundNotShipped({
    paymentStatus: 'escrow',
    fulfillmentStatus: 'awaiting_shipment',
    createdAt: '2026-09-16T00:00:00.000Z',
  }, now), false);
  assert.equal(_test.canAutoRefundNotShipped({
    paymentStatus: 'escrow',
    shippedAt: '2026-09-11T00:00:00.000Z',
    createdAt: '2026-09-10T00:00:00.000Z',
  }, now), false);
});

function nativeItem(overrides = {}) {
  return {
    card: { id: '548832', name: 'Mew ex' },
    listingId: '1234',
    sellerUid: 'seller-uid',
    quantity: 2,
    unitPricePkn: 1,
    totalPricePkn: 2,
    nftAvailable: true,
    reserveAvailable: true,
    source: 'pokoin_user_listing',
    sourceListingId: '',
    sourceMetadata: {},
    ...overrides,
  };
}

test('checkout re-prices native listings from price_pkn, never the client body', async () => {
  const calls = [];
  const { _test } = loadMarketplaceOrdersWithStubs({
    query: async (sql, values) => {
      calls.push({ sql, values });
      if (/update public\.marketplace_user_listings/.test(sql)) {
        return { rows: [{ card_id: '548832', seller_uid: 'seller-uid', quantity_available: 3, price_pkn: '60128.000000', nft_available: false, reserve_available: false }] };
      }
      return { rows: [] };
    },
  });
  const item = nativeItem({ unitPricePkn: 70000, totalPricePkn: 140000 });
  await _test.verifyAndDecrementListings([item]);
  const update = calls.find((call) => /update public\.marketplace_user_listings/.test(call.sql));
  assert.match(update.sql, /price_pkn <= \$4/);
  assert.deepEqual(update.values, ['1234', 2, 'seller-uid', 70000]);
  assert.equal(item.unitPricePkn, 60128);
  assert.equal(item.totalPricePkn, 120256);
  assert.equal(item.nftAvailable, false);
  assert.equal(item.reserveAvailable, false);
});

test('checkout rejects a native listing the client under-priced', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs({ query: async () => ({ rows: [] }) });
  await assert.rejects(
    () => _test.verifyAndDecrementListings([nativeItem({ unitPricePkn: 1 })]),
    (error) => error.statusCode === 409 && /no longer available at this price/.test(error.message),
  );
});

test('order totals come from re-priced items and ignore the client totalPkn', () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const item = _test.applyServerPrice(nativeItem(), { unitPricePkn: 500, nftAvailable: false, reserveAvailable: false });
  const totals = _test.orderTotals([item], { totalPkn: 999999, shippingPkn: 10, taxPkn: 0 }, 'physical');
  assert.deepEqual(totals, { subtotalPkn: 1000, taxPkn: 0, shippingPkn: 10, totalPkn: 1010 });
  assert.throws(
    () => _test.orderTotals([item], {}, 'nft_only'),
    /NFT-only checkout requires/,
  );
});

test('CardTrader live items are priced from the live offer and credited to pknreserve', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs({
    liveListings: async () => ({ listings: [{ cardtraderProductId: '123', quantity: 4, displayPricePkn: 900 }] }),
  });
  const item = cardTraderItem({ sellerUid: 'attacker-uid', unitPricePkn: 1000, nftAvailable: false });
  await _test.verifyCardTraderLiveItems([item], { reserveSellerUid: 'reserve-uid' });
  assert.equal(item.sellerUid, 'reserve-uid');
  assert.equal(item.unitPricePkn, 900);
  assert.equal(item.totalPricePkn, 900);
  assert.equal(item.nftAvailable, true);

  await assert.rejects(
    () => _test.verifyCardTraderLiveItems([cardTraderItem({ unitPricePkn: 100 })], { reserveSellerUid: 'reserve-uid' }),
    (error) => error.statusCode === 409,
  );
  await assert.rejects(
    () => _test.verifyCardTraderLiveItems([cardTraderItem()], {}),
    (error) => error.statusCode === 503,
  );
});

function fakeFirestore({ order, ledger = [] }) {
  const writes = [];
  const orderRef = { id: 'order-1', kind: 'order' };
  const firestore = {
    collection(name) {
      return {
        doc: (id) => (name === 'orders' ? orderRef : { collection: name, id: id || 'auto' }),
        where: () => ({ limit: () => ({ kind: 'ledger' }) }),
      };
    },
    async runTransaction(fn) {
      const transaction = {
        async get(ref) {
          if (ref.kind === 'ledger') return { docs: ledger.map((entry) => ({ data: () => entry })) };
          return { exists: Boolean(order), data: () => order };
        },
        set(ref, data) { writes.push({ ref, data }); },
      };
      return fn(transaction);
    },
  };
  return { firestore, orderRef, writes };
}

const fakeAdmin = { firestore: { FieldValue: { serverTimestamp: () => 'now', increment: (n) => ({ increment: n }) } } };

test('escrow release refuses an order with no server escrow debit (client-forged order)', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const order = {
    uid: 'buyer-uid',
    paymentStatus: 'escrow',
    totalPkn: 1000000,
    items: [{ sellerUid: 'buyer-uid', quantity: 1, totalPricePkn: 1000000 }],
  };
  const { firestore, orderRef, writes } = fakeFirestore({ order });
  orderRef.get = async () => ({ exists: true, data: () => order });
  await assert.rejects(
    () => _test.confirmDelivery({ admin: fakeAdmin, firestore, decoded: { uid: 'buyer-uid' }, orderId: 'order-1' }),
    (error) => error.statusCode === 409 && /no escrow payment/.test(error.message),
  );
  assert.equal(writes.length, 0);
});

test('escrow release pays sellers only when the escrow ledger debit matches the order total', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const order = {
    uid: 'buyer-uid',
    paymentStatus: 'escrow',
    totalPkn: 1000,
    items: [{ sellerUid: 'seller-uid', quantity: 1, totalPricePkn: 1000 }],
  };
  const { firestore, orderRef, writes } = fakeFirestore({
    order,
    ledger: [{ uid: 'buyer-uid', type: 'marketplace_order_escrow', amountPkn: -1000, orderId: 'order-1' }],
  });
  orderRef.get = async () => ({ exists: true, data: () => order });
  await _test.confirmDelivery({ admin: fakeAdmin, firestore, decoded: { uid: 'buyer-uid' }, orderId: 'order-1' });
  const credit = writes.find((write) => write.ref.collection === 'balances');
  assert.equal(credit.ref.id, 'seller-uid');
  assert.deepEqual(credit.data.availablePkn, { increment: 1000 });
});

test('escrow release re-reads the order in the transaction so a second release is refused', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const staleOrder = { uid: 'buyer-uid', paymentStatus: 'escrow', totalPkn: 1000, items: [] };
  const settledOrder = { ...staleOrder, paymentStatus: 'released' };
  const { firestore, orderRef, writes } = fakeFirestore({
    order: settledOrder,
    ledger: [{ uid: 'buyer-uid', type: 'marketplace_order_escrow', amountPkn: -1000 }],
  });
  orderRef.get = async () => ({ exists: true, data: () => staleOrder });
  await assert.rejects(
    () => _test.confirmDelivery({ admin: fakeAdmin, firestore, decoded: { uid: 'buyer-uid' }, orderId: 'order-1' }),
    /not in escrow/,
  );
  assert.equal(writes.length, 0);
});

test('not-shipped auto refund refuses a forged escrow order', async () => {
  const { _test } = loadMarketplaceOrdersWithStubs();
  const order = {
    uid: 'buyer-uid',
    paymentStatus: 'escrow',
    totalPkn: 5000000,
    createdAt: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
    items: [],
  };
  const { firestore, orderRef, writes } = fakeFirestore({ order });
  orderRef.get = async () => ({ exists: true, data: () => order });
  await assert.rejects(
    () => _test.reportProblem({ admin: fakeAdmin, firestore, decoded: { uid: 'buyer-uid' }, orderId: 'order-1', reason: 'not_shipped' }),
    (error) => error.statusCode === 409,
  );
  assert.equal(writes.length, 0);
});
