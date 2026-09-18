'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const apiDir = __dirname;
const sql = fs.readFileSync(path.join(apiDir, '../oracle-postgres/schema/083_jumbo_product_type.sql'), 'utf8');
const cards = fs.readFileSync(path.join(apiDir, 'marketplace-cards.js'), 'utf8');
const reactSql = fs.readFileSync(path.join(apiDir, '_marketplace_react_sql.js'), 'utf8');
const redirect = fs.readFileSync(path.join(apiDir, 'cardmarket-redirect.js'), 'utf8');

test('category 78 maps to the jumbo product type, not card', () => {
  assert.match(sql, /when 78 then 'jumbo'/);
  assert.doesNotMatch(sql, /when 78 then 'card'/);
});

test('jumbos stay item_kind single through ingest and re-derivation', () => {
  // apply_cardtrader_category_kind + refresh_marketplace_cards_from_blueprints
  const occurrences = (sql.match(/in \('card', 'jumbo'\) then 'single'/g) || []).length;
  assert.equal(occurrences, 3, 'apply() x2 + refresh() x1 keep jumbos as singles');
  assert.match(sql, /select public\.apply_cardtrader_category_kind\(\);/);
});

test('jumbo card surfaces keep jumbos visible: search, set desks, canonical redirects', () => {
  assert.match(cards, /product_type in \('card', 'jumbo'\)/);
  assert.match(cards, /typedProduct === 'card'[\s\S]*?productType === 'jumbo'/);
  assert.match(reactSql, /and c\.product_type in \('card', 'jumbo'\)/);
  assert.match(redirect, /versions\.product_type in \('card', 'jumbo'\)/);
});
