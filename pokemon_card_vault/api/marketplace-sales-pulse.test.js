'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { metricName, rankLeaders, readTrend } = require('./marketplace-sales-pulse');

function rawCard(id, units, events) {
  return {
    id: String(id),
    card_id: String(id),
    name: `Card ${id}`,
    set: 'Test Set',
    salesDay: '2026-09-10',
    dailySoldQty: units,
    dailySaleSamples: events,
  };
}

test('metricName defaults to observed sales and keeps quantity diagnostic-only', () => {
  assert.equal(metricName('events'), 'sales');
  assert.equal(metricName('anything'), 'sales');
  assert.equal(metricName('units'), 'quantity');
});

test('rankLeaders defaults to observed sales instead of removed quantity', () => {
  const cards = [rawCard(2, 500, 2), rawCard(4, 74, 17)];
  assert.equal(rankLeaders(cards, 'sales', 2)[0].card.id, '4');
  assert.equal(rankLeaders(cards, 'quantity', 2)[0].card.id, '2');
  assert.equal(rankLeaders(cards, 'sales', 1)[0].observedSales, 17);
});

test('readTrend normalizes database counters', async () => {
  const query = async (_sql, values) => {
    assert.deepEqual(values, [7]);
    return { rows: [{ day: '2026-09-10', removed_listing_quantity: '12', observed_sales: '8', active_cards: 6 }] };
  };
  assert.deepEqual(await readTrend(7, query), [{
    day: '2026-09-10', observedSales: 8, removedListingQuantity: 12, activeCards: 6,
  }]);
});
