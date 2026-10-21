const assert = require('node:assert/strict');
const test = require('node:test');

const {
  handleCompletedCheckout,
  paymentIntentIdFromSession,
} = require('./_pkn_purchase');

function createFakeAdmin({ existingPurchase = null } = {}) {
  const store = {
    purchases: new Map(),
    balances: new Map(),
    ledger: [],
  };
  if (existingPurchase) {
    store.purchases.set(existingPurchase.id, { ...existingPurchase.data });
  }

  const FieldValue = {
    serverTimestamp: () => ({ __type: 'serverTimestamp' }),
    increment: (n) => ({ __type: 'increment', n }),
  };

  function docRef(collectionName, id) {
    return {
      id: id || `auto_${store.ledger.length + 1}`,
      collectionName,
      get: async () => {
        if (collectionName === 'pkn_purchases') {
          const data = store.purchases.get(id);
          return { exists: Boolean(data), data: () => data };
        }
        return { exists: false, data: () => undefined };
      },
    };
  }

  const firestore = {
    collection(name) {
      return {
        doc(id) {
          return docRef(name, id);
        },
      };
    },
    async runTransaction(fn) {
      const transaction = {
        async get(ref) {
          return ref.get();
        },
        set(ref, data, options = {}) {
          if (ref.collectionName === 'pkn_purchases') {
            store.purchases.set(ref.id, { ...data });
            return;
          }
          if (ref.collectionName === 'balances') {
            const prev = store.balances.get(ref.id) || {};
            if (options.merge) {
              const next = { ...prev };
              for (const [key, value] of Object.entries(data)) {
                if (value && value.__type === 'increment') {
                  next[key] = Number(prev[key] || 0) + Number(value.n || 0);
                } else {
                  next[key] = value;
                }
              }
              store.balances.set(ref.id, next);
            } else {
              store.balances.set(ref.id, { ...data });
            }
            return;
          }
          if (ref.collectionName === 'ledger_entries') {
            store.ledger.push({ id: ref.id, ...data });
          }
        },
      };
      await fn(transaction);
    },
  };

  const firestoreFn = () => firestore;
  firestoreFn.FieldValue = FieldValue;

  return {
    admin: {
      firestore: firestoreFn,
    },
    store,
  };
}

test('paymentIntentIdFromSession accepts string or expanded object', () => {
  assert.equal(paymentIntentIdFromSession({ payment_intent: 'pi_123' }), 'pi_123');
  assert.equal(
    paymentIntentIdFromSession({ payment_intent: { id: 'pi_expanded' } }),
    'pi_expanded',
  );
  assert.equal(paymentIntentIdFromSession({}), '');
});

test('handleCompletedCheckout credits once and is idempotent on retry', async () => {
  const { admin, store } = createFakeAdmin();
  const session = {
    id: 'cs_test_1',
    payment_intent: { id: 'pi_test_1' },
    amount_total: 500,
    currency: 'eur',
    customer_details: { email: 'buyer@example.com' },
    metadata: {
      uid: 'user_1',
      pknAmount: '1000',
      fiatCents: '500',
      email: 'buyer@example.com',
    },
  };

  const first = await handleCompletedCheckout({ admin, session });
  assert.deepEqual(first, {
    amountPkn: 1000,
    fulfillmentTarget: 'site_credit',
    status: 'credited',
  });
  assert.equal(store.balances.get('user_1').availablePkn, 1000);
  assert.equal(store.ledger.length, 1);
  assert.equal(store.purchases.get('cs_test_1').stripePaymentIntentId, 'pi_test_1');

  const second = await handleCompletedCheckout({ admin, session });
  assert.equal(second.status, 'credited');
  assert.equal(second.amountPkn, 1000);
  assert.equal(store.balances.get('user_1').availablePkn, 1000);
  assert.equal(store.ledger.length, 1);
});

test('handleCompletedCheckout rejects invalid metadata', async () => {
  const { admin } = createFakeAdmin();
  await assert.rejects(
    () =>
      handleCompletedCheckout({
        admin,
        session: { id: 'cs_bad', metadata: { uid: 'u1', pknAmount: '0' } },
      }),
    /Invalid checkout metadata/,
  );
});
