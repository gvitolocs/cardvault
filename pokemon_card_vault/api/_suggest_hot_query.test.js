'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  rememberHotSuggestQuery,
  takeHotSuggestCandidates,
  resetHotSuggestQuery,
} = require('./_suggest_hot_query');

test('hot suggest pool serves offset 0 IDs then ignores load-more offsets', () => {
  resetHotSuggestQuery();
  rememberHotSuggestQuery('oshaw', 'en', [
    { card_id: '1' },
    { card_id: '2' },
    { id: '2' },
    { card_id: '3' },
  ], 98);
  const first = takeHotSuggestCandidates('oshaw', 'en', 49, 0);
  assert.deepEqual(first.map((row) => row.card_id), ['1', '2', '3']);
  assert.equal(first[0].hot_suggest, true);
  assert.equal(takeHotSuggestCandidates('oshaw', 'en', 49, 48), null);
  assert.equal(takeHotSuggestCandidates('oshawt', 'en', 49, 0), null);
});

test('SUGGEST_HOT_QUERY=0 stores nothing', () => {
  resetHotSuggestQuery();
  const previous = process.env.SUGGEST_HOT_QUERY;
  process.env.SUGGEST_HOT_QUERY = '0';
  try {
    rememberHotSuggestQuery('oshaw', 'en', [{ card_id: '1' }], 1);
    assert.equal(takeHotSuggestCandidates('oshaw', 'en', 10, 0), null);
  } finally {
    if (previous === undefined) {
      delete process.env.SUGGEST_HOT_QUERY;
    } else {
      process.env.SUGGEST_HOT_QUERY = previous;
    }
    resetHotSuggestQuery();
  }
});
