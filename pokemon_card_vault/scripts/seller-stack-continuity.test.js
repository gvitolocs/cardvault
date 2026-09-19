const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const schemaDir = `${__dirname}/../oracle-postgres/schema`;
const migration = fs.readFileSync(`${schemaDir}/088_seller_stack_continuity.sql`, 'utf8');
const refresh = fs.readFileSync(`${schemaDir}/086_disappearance_inferred_sales.sql`, 'utf8');
const behaviour = fs.readFileSync(
  `${__dirname}/../oracle-postgres/tests/088_seller_stack_continuity.test.sql`,
  'utf8',
);
const manifest = JSON.parse(fs.readFileSync(`${__dirname}/../oracle-postgres/schema-manifest.json`, 'utf8'));

// The behavioural proofs live in the SQL suite; these guard the invariants that
// are easy to regress silently in review.

test('continuity is decided by quantity, not by mere existence of a successor', () => {
  assert.match(migration, /continuity_qty/);
  assert.match(migration, /residual_qty/);
  // least(P, available successor) / remainder stays a sale
  assert.match(migration, /least\(a\.quantity::bigint, a\.succ_qty - a\.consumed_before\)/);
  // a residual is never auto-finalised: it stays provisional
  assert.match(migration, /set quantity = p\.residual_qty,\s*\n\s*status = 'provisional'/);
});

test('successor units are allocated once per stack', () => {
  assert.match(migration, /consumed_before/);
  assert.match(migration, /rows between unbounded preceding and 1 preceding/);
});

test('reconciliation is idempotent: credited continuity consumes capacity', () => {
  assert.match(migration, /credited/);
  assert.match(migration, /archive_metadata \? 'continuityQuantity'/);
  assert.match(
    migration,
    /greatest\(coalesce\(sc\.succ_qty, 0\) - coalesce\(cr\.credited_qty, 0\), 0\)/,
  );
});

test('continuity keys on the authoritative seller-stack facets only', () => {
  for (const facet of ['seller_account_id', 'bp', 'cond', 'lang', 'is_rev', 'is_first', 'is_graded']) {
    assert.match(migration, new RegExp(`\\b${facet}\\b`));
  }
  // never identified by card or listing name
  assert.doesNotMatch(migration, /seller_account_name\s*=/);
});

test('quantity_decreased episodes are never reconciled', () => {
  assert.match(migration, /h\.archive_reason = 'inferred_sale'/);
  assert.doesNotMatch(migration, /archive_reason = 'quantity_decreased'/);
});

test('no card, blueprint or date is special-cased', () => {
  assert.doesNotMatch(migration, /2026-\d\d-\d\d/);
  assert.doesNotMatch(migration, /389944|779888|111246/);
});

test('refresh reconciles the whole correction window after a valid complete book', () => {
  const upsert = refresh.indexOf('get diagnostics upserted_count = row_count;');
  const reconcile = refresh.indexOf('perform public.reconcile_cardtrader_seller_stack_continuity');
  assert.ok(upsert >= 0);
  assert.ok(reconcile > upsert, 'continuity must run after the incoming snapshot is installed');
  assert.match(refresh.slice(reconcile - 180, reconcile), /if v_can_archive[\s\S]*sanity\.suspicious/);
  // the whole correction window, not just the previous day
  assert.match(refresh.slice(reconcile, reconcile + 220), /v_window_from,\s*\n\s*v_removed_day/);
});

test('the boolean retraction path does not clobber a reconciled residual', () => {
  assert.match(refresh, /not \(h\.archive_metadata \? 'continuityQuantity'\)/);
});

test('the behavioural SQL suite covers the required invariants', () => {
  for (const marker of ['T1:', 'T2:', 'T3:', 'T4:', 'T5:', 'T6:', 'T7:', 'T8:', 'T9:', 'T10:']) {
    assert.ok(behaviour.includes(marker), `missing ${marker}`);
  }
  assert.match(behaviour, /idempotent/);
});

test('the migration is registered in the schema manifest', () => {
  assert.ok(manifest.files.includes('088_seller_stack_continuity.sql'));
});
