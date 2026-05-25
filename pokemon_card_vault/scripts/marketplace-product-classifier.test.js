const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const schemaSql = fs.readFileSync(
  path.join(__dirname, '..', 'oracle-postgres', 'schema', '002_marketplace_functions.sql'),
  'utf8',
);

function classifierBody() {
  const match = schemaSql.match(
    /create or replace function public\.classify_marketplace_product_type[\s\S]+?\$\$;/,
  );
  assert.ok(match, 'classifier function exists in Oracle schema');
  return match[0];
}

test('product classifier bounds product tokens so Pokemon names are not products', () => {
  const sql = classifierBody();

  assert.match(sql, /when has_collector_number\s+then 'card'/);
  assert.match(sql, /\(\^|\[\^a-z0-9]\)\(tin\|tins\)\(\[\^a-z0-9]\|\$\)/);
  assert.match(sql, /\(\^|\[\^a-z0-9]\)\(premium collection\|special collection/);
  assert.doesNotMatch(sql, /name ~ 'booster\|pack'/);
  assert.doesNotMatch(sql, /name ~ 'box\|display\|etb\|elite trainer'/);
  assert.doesNotMatch(sql, /name ~ 'deck\|starter\|theme deck'/);
  assert.doesNotMatch(sql, /collection\|collector\.\?s\? chest\|bundle\|tin\|empty mini/);
});

test('product classifier keeps known false-positive names covered', () => {
  const sql = classifierBody();

  const boundedProductTokenChecks = [
    '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)',
    '(^|[^a-z0-9])(premium collection|special collection',
    '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)',
  ];

  for (const name of ['Giratina', 'Victini', 'Dratini', 'Mantine', 'Tinkaton', 'Pincurchin']) {
    for (const boundedCheck of boundedProductTokenChecks) {
      assert.ok(sql.includes(boundedCheck), `${name} is protected by bounded product-token matching`);
    }
  }
});
