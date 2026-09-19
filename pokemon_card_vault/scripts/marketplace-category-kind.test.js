const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const schemaSql = fs.readFileSync(
  path.join(__dirname, '..', 'oracle-postgres', 'schema', '060_cardtrader_category_kind.sql'),
  'utf8',
);

test('CardTrader category ids beat empty category_name for accessories', () => {
  assert.match(schemaSql, /when 73 then 'card'/);
  assert.match(schemaSql, /when 78 then 'card'/);
  assert.match(schemaSql, /when 61 then 'accessory'/);
  assert.match(schemaSql, /when 60 then 'collection_box'/);
  assert.match(schemaSql, /when 118 then 'accessory'/);
  assert.match(schemaSql, /when 66 then 'booster_pack'/);
  assert.match(schemaSql, /create table if not exists public\.marketplace_visual_kind/);
  assert.match(schemaSql, /resolved_marketplace_product_type/);
  assert.match(schemaSql, /b\.category_id/);
  assert.doesNotMatch(schemaSql, /<> 'card'/);
  assert.doesNotMatch(schemaSql, /public\.classify_marketplace_product_type\(\s*b\.name/);
});
