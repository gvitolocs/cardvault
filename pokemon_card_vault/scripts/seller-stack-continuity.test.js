const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  `${__dirname}/../oracle-postgres/schema/088_seller_stack_continuity.sql`,
  'utf8',
);
const refresh = fs.readFileSync(
  `${__dirname}/../oracle-postgres/schema/086_disappearance_inferred_sales.sql`,
  'utf8',
);
const manifest = JSON.parse(fs.readFileSync(
  `${__dirname}/../oracle-postgres/schema-manifest.json`,
  'utf8',
));

test('continuity migration uses the authoritative seller-stack facets', () => {
  assert.match(migration, /cardtrader_same_seller_listing_stack/);
  assert.match(migration, /history\.removed_day = p_observed_day - 1/);
  assert.match(migration, /history\.archive_reason = 'inferred_sale'/);
  assert.match(migration, /history\.status in \('confirmed', 'provisional', 'pending'\)/);
  assert.match(migration, /status = 'retracted'/);
  assert.match(migration, /resolved_at = now\(\)/);
  assert.match(migration, /seller_stack_reappeared_next_valid_observation/);
  assert.doesNotMatch(migration, /quantity_decreased/);
  assert.doesNotMatch(migration, /2026-\d\d-\d\d/);
});

test('refresh invokes continuity only after a valid complete-book refresh', () => {
  const upsert = refresh.indexOf('get diagnostics upserted_count = row_count;');
  const reconcile = refresh.indexOf('reconcile_cardtrader_seller_stack_continuity');
  assert.ok(upsert >= 0);
  assert.ok(reconcile > upsert);
  assert.match(refresh.slice(reconcile - 180, reconcile), /if v_can_archive[\s\S]*sanity\.suspicious/);
  assert.equal(manifest.files.at(-1), '088_seller_stack_continuity.sql');
});
