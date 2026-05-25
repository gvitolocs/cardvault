const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cleanWatchlistAction,
  recordWatchlistChange,
} = require('./_marketplace_watchlist_analytics');

test('watchlist analytics normalizes add/remove actions', () => {
  assert.equal(cleanWatchlistAction('added'), 'add');
  assert.equal(cleanWatchlistAction('watchlist_remove'), 'remove');
  assert.equal(cleanWatchlistAction('noop'), '');
});

test('signed-in watchlist add is idempotent through membership insert', async () => {
  const calls = [];
  const result = await recordWatchlistChange({
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ watchlist_count: 7, changed: true }] };
    },
    cardId: 316600,
    action: 'add',
    userUid: 'user-1',
  });

  assert.deepEqual(result, {
    cardId: '316600',
    action: 'add',
    changed: true,
    watchlistCount: 7,
    userScoped: true,
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /marketplace_card_watchlist_users/);
  assert.match(calls[0].sql, /on conflict \(blueprint_id, user_uid\) do nothing/);
  assert.match(calls[0].sql, /marketplace_card_watchlist_analytics/);
  assert.deepEqual(calls[0].values, [316600, 'user-1']);
});

test('watchlist remove decrements bounded at zero', async () => {
  const calls = [];
  const result = await recordWatchlistChange({
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ watchlist_count: 0, changed: true }] };
    },
    cardId: '316600',
    action: 'remove',
  });

  assert.equal(result.watchlistCount, 0);
  assert.equal(result.userScoped, false);
  assert.match(calls[0].sql, /greatest\(0, watchlist_count - 1\)/);
  assert.deepEqual(calls[0].values, [316600]);
});

test('watchlist analytics rejects invalid payloads', async () => {
  await assert.rejects(
    recordWatchlistChange({
      query: async () => ({ rows: [] }),
      cardId: 'not-a-card',
      action: 'add',
    }),
    /Invalid watchlist analytics payload/,
  );
});
