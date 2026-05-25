const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cleanCartAction,
  holderKeyFor,
  recordCartChange,
} = require('./_marketplace_cart_analytics');

test('cart analytics normalizes add/remove actions', () => {
  assert.equal(cleanCartAction('add_to_cart'), 'add');
  assert.equal(cleanCartAction('cart_remove'), 'remove');
  assert.equal(cleanCartAction('noop'), '');
});

test('cart analytics prefers signed-in holder key over anonymous id', () => {
  assert.equal(holderKeyFor({ userUid: 'user-1', anonymousId: 'anon-1' }), 'uid:user-1');
  assert.equal(holderKeyFor({ anonymousId: 'anon-1' }), 'anon:anon-1');
  assert.equal(holderKeyFor({}), '');
});

test('cart add is idempotent through holder membership insert', async () => {
  const calls = [];
  const result = await recordCartChange({
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ cart_holder_count: 7, changed: true }] };
    },
    cardId: 316600,
    action: 'add',
    userUid: 'user-1',
  });

  assert.deepEqual(result, {
    cardId: '316600',
    action: 'add',
    changed: true,
    cartHolderCount: 7,
    userScoped: true,
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /marketplace_card_cart_users/);
  assert.match(calls[0].sql, /on conflict \(blueprint_id, holder_key\) do nothing/);
  assert.match(calls[0].sql, /marketplace_card_cart_analytics/);
  assert.deepEqual(calls[0].values, [316600, 'uid:user-1']);
});

test('cart remove decrements bounded at zero for anonymous holders', async () => {
  const calls = [];
  const result = await recordCartChange({
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ cart_holder_count: 0, changed: true }] };
    },
    cardId: '316600',
    action: 'remove',
    anonymousId: 'anon-1',
  });

  assert.equal(result.cartHolderCount, 0);
  assert.equal(result.userScoped, false);
  assert.match(calls[0].sql, /greatest\(0, cart_holder_count - 1\)/);
  assert.deepEqual(calls[0].values, [316600, 'anon:anon-1']);
});

test('cart analytics rejects missing holder identity', async () => {
  await assert.rejects(
    recordCartChange({
      query: async () => ({ rows: [] }),
      cardId: 316600,
      action: 'add',
    }),
    /Invalid cart analytics payload/,
  );
});
