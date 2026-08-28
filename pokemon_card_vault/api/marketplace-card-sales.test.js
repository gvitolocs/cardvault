const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeOracleSale,
  normalizeSaleItem,
} = require('./marketplace-card-sales');

test('normalizeSaleItem returns anonymized raw sale data', () => {
  const sale = normalizeSaleItem('order-1', '2026-05-22T19:00:00.000Z', {
    card: { id: '123' },
    quantity: 2,
    totalPricePkn: 60,
    condition: 'SP',
    sellerUid: 'private',
  });

  assert.deepEqual(sale, {
    orderId: 'order-1',
    cardId: '123',
    condition: 'SP',
    pricePkn: 30,
    quantity: 2,
    soldAt: '2026-05-22T19:00:00.000Z',
    graded: false,
    gradingCompany: '',
    grade: '',
  });
});

test('normalizeSaleItem keeps only slab brand and grade for graded sales', () => {
  const sale = normalizeSaleItem('order-2', '2026-05-22T20:00:00.000Z', {
    cardId: '456',
    unitPricePkn: 180,
    quantity: 1,
    condition: 'NM',
    graded: true,
    gradingCompany: 'PSA',
    grade: '10',
    certificationId: 'hidden',
  });

  assert.equal(sale.cardId, '456');
  assert.equal(sale.pricePkn, 180);
  assert.equal(sale.graded, true);
  assert.equal(sale.gradingCompany, 'PSA');
  assert.equal(sale.grade, '10');
  assert.equal('certificationId' in sale, false);
});

test('normalizeOracleSale maps CardTrader removed observations to chart events', () => {
  const sale = normalizeOracleSale({
    id: 'obs-1',
    blueprint_id: 316600,
    source: 'cardtrader_removed_sale',
    source_item_id: 'cardtrader:uid:listing-1:2026-05-23',
    observed_at: '2026-05-23T00:00:00.000Z',
    price_pkn: '2598',
    quantity: 1,
    condition: 'NM',
    graded: false,
  });

  assert.deepEqual(sale, {
    orderId: 'cardtrader:uid:listing-1:2026-05-23',
    cardId: '316600',
    condition: 'NM',
    pricePkn: 2598,
    quantity: 1,
    soldAt: '2026-05-23T00:00:00.000Z',
    graded: false,
    gradingCompany: '',
    grade: '',
    source: 'cardtrader_removed_sale',
  });
});
