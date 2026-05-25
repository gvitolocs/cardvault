const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildSellerSaleEmail,
  groupOrderItemsBySeller,
  marketplaceEmailFrom,
  notificationMarkerId,
  orderIsPaid,
  sendSellerSaleNotificationsForPaidOrder,
} = require('./_marketplace_sale_notifications');

function adminStub() {
  return {
    firestore: {
      FieldValue: {
        serverTimestamp: () => 'SERVER_TIMESTAMP',
      },
    },
  };
}

test('marketplaceEmailFrom is fixed to market@pokoin.com', () => {
  const previous = process.env.MARKETPLACE_EMAIL_FROM;
  process.env.MARKETPLACE_EMAIL_FROM = 'Other <other@example.com>';
  assert.equal(marketplaceEmailFrom(), 'market@pokoin.com');
  if (previous === undefined) {
    delete process.env.MARKETPLACE_EMAIL_FROM;
  } else {
    process.env.MARKETPLACE_EMAIL_FROM = previous;
  }
});

test('groupOrderItemsBySeller groups multiple sold cards into one seller email group', () => {
  const groups = groupOrderItemsBySeller([
    {
      sellerUid: 'seller-a',
      sellerName: 'Ash',
      card: { name: 'Pikachu' },
      quantity: 1,
      unitPricePkn: 100,
      totalPricePkn: 100,
    },
    {
      sellerUid: 'seller-b',
      sellerName: 'Misty',
      card: { name: 'Staryu' },
      quantity: 1,
      unitPricePkn: 80,
      totalPricePkn: 80,
    },
    {
      sellerUid: 'seller-a',
      sellerName: 'Ash',
      card: { name: 'Charizard' },
      quantity: 2,
      unitPricePkn: 500,
      totalPricePkn: 1000,
    },
  ]);

  assert.equal(groups.length, 2);
  const ash = groups.find((group) => group.sellerUid === 'seller-a');
  assert.equal(ash.items.length, 2);
  assert.equal(ash.quantity, 3);
  assert.equal(ash.totalPkn, 1100);
});

test('seller sale email lists sold cards without buyer email', () => {
  const email = buildSellerSaleEmail({
    orderId: 'order-123',
    sellerGroup: {
      sellerUid: 'seller-a',
      sellerName: 'Ash',
      quantity: 2,
      totalPkn: 240,
      items: [
        {
          card: { name: 'Pikachu' },
          quantity: 2,
          unitPricePkn: 120,
          totalPricePkn: 240,
          condition: 'NM',
          language: 'EN',
          buyerNotes: 'Please pack carefully.',
        },
      ],
    },
  });

  assert.match(email.subject, /You sold 2 cards/);
  assert.match(email.text, /Pikachu - NM - EN x 2/);
  assert.match(email.text, /Seller payout credited: 240 PKN/);
  assert.match(email.text, /Please pack carefully/);
  assert.doesNotMatch(email.text, /buyer@example\.com/);
});

test('paid order notification sends once per seller and respects claimed markers', async () => {
  const sent = [];
  const claimed = new Set();
  const orderData = {
    paymentStatus: 'paid',
    items: [
      {
        sellerUid: 'seller-a',
        sellerName: 'Ash',
        card: { name: 'Pikachu' },
        quantity: 1,
        unitPricePkn: 100,
        totalPricePkn: 100,
      },
      {
        sellerUid: 'seller-a',
        sellerName: 'Ash',
        card: { name: 'Raichu' },
        quantity: 1,
        unitPricePkn: 150,
        totalPricePkn: 150,
      },
      {
        sellerUid: 'seller-b',
        sellerName: 'Misty',
        card: { name: 'Staryu' },
        quantity: 1,
        unitPricePkn: 80,
        totalPricePkn: 80,
      },
    ],
  };
  const claimNotificationFn = async ({ orderId, sellerUid }) => {
    const id = notificationMarkerId(orderId, sellerUid);
    if (claimed.has(id)) {
      return { claimed: false, markerRef: { set: async () => {} } };
    }
    claimed.add(id);
    return { claimed: true, markerRef: { set: async () => {} } };
  };
  const lookupSellerFn = async ({ sellerUid }) => ({
    email: `${sellerUid}@example.com`,
  });
  const sendEmailFn = async (message) => {
    sent.push(message);
    return { ok: true, id: `email-${sent.length}` };
  };

  const first = await sendSellerSaleNotificationsForPaidOrder({
    admin: adminStub(),
    firestore: {},
    orderId: 'order-123',
    orderData,
    lookupSellerFn,
    claimNotificationFn,
    markNotificationFn: async () => {},
    sendEmailFn,
  });
  const second = await sendSellerSaleNotificationsForPaidOrder({
    admin: adminStub(),
    firestore: {},
    orderId: 'order-123',
    orderData,
    lookupSellerFn,
    claimNotificationFn,
    markNotificationFn: async () => {},
    sendEmailFn,
  });

  assert.equal(first.sellerNotifications.length, 2);
  assert.equal(sent.length, 2);
  assert.equal(sent.filter((message) => message.to === 'seller-a@example.com').length, 1);
  assert.match(sent.find((message) => message.to === 'seller-a@example.com').text, /Raichu/);
  assert.equal(second.sellerNotifications.length, 2);
  assert.equal(sent.length, 2);
});

test('notifications skip unpaid orders', async () => {
  assert.equal(orderIsPaid({ paymentStatus: 'reserved' }), false);
  const result = await sendSellerSaleNotificationsForPaidOrder({
    admin: adminStub(),
    firestore: {},
    orderId: 'order-123',
    orderData: { paymentStatus: 'reserved', items: [] },
    sendEmailFn: async () => {
      throw new Error('should not send');
    },
  });

  assert.equal(result.skipped, true);
});
