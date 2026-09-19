const assert = require('node:assert/strict');
const test = require('node:test');
const { splitNeighborRows, candidateColumns, expansionSlugSql, overlayCheapestOnRows } = require('./_marketplace_react_sql');
const { runWithGame } = require('./_marketplace_game');

test('expansionSlugSql matches JS slugify for ampersand set names', () => {
  const sql = expansionSlugSql('name');
  assert.match(sql, /replace\(public\.unaccent\(name\), '&', ' and '\)/);
  assert.match(sql, /regexp_replace/);
  assert.match(sql, /trim\(both '-' from/);
});

test('splitNeighborRows takes three wrapping prev and next', () => {
  const packed = splitNeighborRows([
    { card_id: 2, dist_next: 1, dist_prev: 4 },
    { card_id: 3, dist_next: 2, dist_prev: 3 },
    { card_id: 4, dist_next: 3, dist_prev: 2 },
    { card_id: 5, dist_next: 4, dist_prev: 1 },
  ], 3);
  assert.deepEqual(packed.next.map((row) => row.card_id), [2, 3, 4]);
  assert.deepEqual(packed.prev.map((row) => row.card_id), [5, 4, 3]);
});

test('candidateColumns omit c.version on isolated game catalogs', () => {
  assert.match(candidateColumns(), /\bc\.emoji\b/);
  assert.match(candidateColumns(), /\bc\.version\b/);
  assert.match(candidateColumns(), /\bc\.art_layout\b/);
  assert.match(candidateColumns(), /\bc\.artist\b/);
  assert.match(candidateColumns(), /\bc\.illustrator\b/);
  assert.doesNotMatch(candidateColumns(), /marketplace_blueprint_artists/);
  assert.doesNotMatch(candidateColumns(), /null::text as version/);
  runWithGame('riftbound', () => {
    const sql = candidateColumns();
    assert.match(sql, /null::text as version/);
    assert.match(sql, /null::text as art_layout/);
    assert.match(sql, /null::text as artist/);
    assert.doesNotMatch(sql, /\bc\.version\b/);
    assert.doesNotMatch(sql, /\bc\.art_layout\b/);
    assert.doesNotMatch(sql, /\bc\.artist\b/);
  });
  runWithGame('one_piece', () => {
    assert.match(candidateColumns(), /null::text as version/);
  });
});

test('overlayCheapestOnRows stamps listed PKN from the cheapest cache map', async () => {
  const rows = await overlayCheapestOnRows(
    [{ card_id: 259390, ct_id: 129695, name: 'Spiritomb' }],
    async () => ({
      byCardId: new Map([['259390', { price: 228, stock: 85, hasCardTraderListing: true }]]),
      byBlueprint: new Map(),
    }),
  );
  assert.equal(rows[0].lowest_price_pkn, 228);
  assert.equal(rows[0].has_cardtrader_listing, true);
});

test('overlayCheapestOnRows uses leftover blueprint_id when ct_id is missing', async () => {
  const rows = await overlayCheapestOnRows(
    [{ card_id: 522236, blueprint_id: 261118, name: 'Gastly' }],
    async (_ids, blueprints) => {
      assert.deepEqual(blueprints, [261118]);
      return {
        byCardId: new Map(),
        byBlueprint: new Map([['261118', { price: 226, stock: 765, hasCardTraderListing: true }]]),
      };
    },
  );
  assert.equal(rows[0].lowest_price_pkn, 226);
});
