const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeOracleSale,
  normalizeSaleItem,
  buildSalesSeries,
  buildSalesFilters,
  mergeSoldDailyRows,
  cleanSoldCondition,
  cleanSoldLanguage,
  cleanSoldFlag,
  soldSliceFromSearchParams,
  compactSoldDailySlice,
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
    language: '',
    pricePkn: 2598,
    quantity: 1,
    soldAt: '2026-05-23T00:00:00.000Z',
    graded: false,
    gradingCompany: '',
    grade: '',
    source: 'cardtrader_removed_sale',
  });
});

test('normalizeOracleSale accepts Postgres Date observed_at', () => {
  const sale = normalizeOracleSale({
    id: 'obs-2',
    blueprint_id: 294979,
    source: 'cardtrader_removed_sale',
    source_item_id: 'cardtrader:listing:2026-09-05:inferred_sale',
    observed_at: new Date('2026-09-05T00:00:00.000Z'),
    price_pkn: '866',
    quantity: 3,
    condition: 'Near Mint',
    graded: false,
  });
  assert.equal(sale.soldAt, '2026-09-05T00:00:00.000Z');
  assert.equal(sale.pricePkn, 866);
});

test('Oracle card sales SQL reads stored daily slices, then leftover ct_id', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(path.join(__dirname, 'marketplace-card-sales.js'), 'utf8');

  assert.match(source, /source = 'cardtrader_removed_sale'/);
  assert.match(source, /card_id = \$1::bigint\s+or ct_id = \$1::bigint/);
  assert.match(source, /case when card_id = \$1::bigint then 0 else 1 end/);
  assert.match(source, /limit 1/);
  assert.match(source, /from public\.cardtrader_sold_daily/);
  assert.match(source, /once_sold|having count\(distinct \(observed_at at time zone 'utc'\)::date\) = 1/);
  assert.match(source, /quantity_decreased/);
  assert.match(source, /first_edition/);
  assert.match(source, /soldSliceSql\(2\)/);
  assert.match(source, /includeRows/);
  assert.match(source, /slices/);
  assert.match(source, /function compactSoldDailySlice/);
  assert.match(source, /daily\.missing/);
  assert.doesNotMatch(source, /cardtrader_snapshot/);
  assert.doesNotMatch(source, /where card_id = \$1::bigint or ct_id = \$1::bigint\n/);
});

test('buildSalesSeries rolls daily median PKN and 24h change', () => {
  const series = buildSalesSeries([
    { day: '2026-09-04', median_pkn: 810, min_pkn: 700, max_pkn: 900, sold_qty: 18, listings: 7 },
    { day: '2026-09-05', median_pkn: 866, min_pkn: 740, max_pkn: 980, sold_qty: 30, listings: 7 },
  ]);
  assert.equal(series.days.length, 2);
  assert.equal(series.lastMedianPkn, 866);
  assert.equal(series.change24hPct, Number(((866 - 810) / 810).toFixed(6)));
  assert.equal(series.firstDay, '2026-09-04');
  assert.equal(series.lastDay, '2026-09-05');
  assert.equal(series.days[0].sampleCount, 7);
  assert.equal(series.days[1].sampleCount, 7);
  assert.equal(series.sampleCount, 14);
});

test('CardTrader leftover condition and language strings collapse to desk keys', () => {
  assert.equal(cleanSoldCondition('Near Mint'), 'NM');
  assert.equal(cleanSoldCondition('Lightly Played'), 'SP');
  assert.equal(cleanSoldCondition('good'), 'MP');
  assert.equal(cleanSoldCondition('Played'), 'PL');
  assert.equal(cleanSoldLanguage('ja'), 'JP');
  assert.equal(cleanSoldLanguage('zh-CN'), 'ZH');
  assert.equal(cleanSoldFlag('1st'), true);
  assert.equal(cleanSoldFlag('unlimited'), false);
  assert.equal(cleanSoldFlag(''), null);
  assert.deepEqual(
    soldSliceFromSearchParams(new URLSearchParams('cond=Near%20Mint&lang=it&firstEdition=1&reverse=0')),
    {
      condition: 'NM',
      language: 'IT',
      reverse: false,
      firstEdition: true,
      graded: null,
    },
  );
  assert.deepEqual(
    buildSalesFilters([
      { condition: 'Poor', language: 'JP', reverse: false, first_edition: true, graded: false },
      { condition: 'NM', language: 'EN', reverse: false, first_edition: false, graded: false },
      { condition: 'NM', language: 'EN', reverse: true, first_edition: false, graded: false },
      { condition: 'SP', language: 'IT', reverse: false, first_edition: false, graded: true },
    ]),
    {
      conditions: ['NM', 'SP', 'Poor'],
      languages: ['EN', 'IT', 'JP'],
      reverse: [false, true],
      firstEdition: [false, true],
      graded: [false, true],
    },
  );
  assert.deepEqual(
    buildSalesFilters(
      [
        { condition: 'NM', language: 'EN', reverse: false, first_edition: false, graded: false },
        { condition: 'Poor', language: 'IT', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'FR', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'IT', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'ES', reverse: false, first_edition: false, graded: false },
      ],
      { condition: 'Poor' },
    ),
    {
      conditions: ['NM', 'MP', 'Poor'],
      languages: ['IT'],
      reverse: [false],
      firstEdition: [false],
      graded: [false],
    },
  );
  assert.deepEqual(
    buildSalesFilters(
      [
        { condition: 'NM', language: 'EN', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'FR', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'IT', reverse: false, first_edition: false, graded: false },
        { condition: 'MP', language: 'ES', reverse: false, first_edition: false, graded: false },
      ],
      { language: 'IT' },
    ),
    {
      conditions: ['MP'],
      languages: ['EN', 'IT', 'FR', 'ES'],
      reverse: [false],
      firstEdition: [false],
      graded: [false],
    },
  );
});

test('stored daily slices merge into one median when All is selected', () => {
  const merged = mergeSoldDailyRows([
    { day: '2026-09-04', median_pkn: 10000, min_pkn: 10000, max_pkn: 10000, sold_qty: 2, listings: 2 },
    { day: '2026-09-04', median_pkn: 6000, min_pkn: 6000, max_pkn: 6000, sold_qty: 1, listings: 1 },
    {
      day: '2026-09-05',
      median_pkn: 15000,
      min_pkn: 15000,
      max_pkn: 15000,
      sold_qty: 1,
      listings: 1,
      graded_comments: ['tiny whitening'],
    },
  ]);
  const four = merged.find((row) => row.day === '2026-09-04');
  assert.equal(four.median_pkn, 10000);
  assert.equal(four.sold_qty, 3);
  assert.equal(four.sample_count, 3);
  const five = merged.find((row) => row.day === '2026-09-05');
  assert.deepEqual(five.comments, ['tiny whitening']);
});

test('sales SQL aggregates the requested slice on the Pi and does not dump observations', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(path.join(__dirname, 'marketplace-card-sales.js'), 'utf8');
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'oracle-postgres', 'schema', '042_cardtrader_sold_daily.sql'),
    'utf8',
  );
  assert.match(source, /select distinct/);
  assert.match(source, /function readOracleSalesFilters/);
  assert.match(source, /includeRows/);
  assert.match(source, /cardtrader_sold_daily/);
  assert.doesNotMatch(source, /select \*\s+from public.marketplace_price_observations/);
  assert.match(sql, /first_edition boolean not null default false/);
  assert.match(sql, /sample_count integer not null default 0/);
  assert.match(sql, /count\(\*\)::integer as sample_count/);
});

test('slices=1 payload is one camelCase row per stored daily combination', () => {
  assert.deepEqual(
    compactSoldDailySlice({
      day: new Date('2026-09-04T00:00:00.000Z'),
      condition: 'Poor',
      language: 'it',
      reverse: false,
      first_edition: false,
      graded: false,
      median_pkn: '12.5',
      min_pkn: '10',
      max_pkn: '14',
      sold_qty: 1,
      listings: 1,
      sample_count: 1,
      graded_comments: ['whitening'],
    }),
    {
      day: '2026-09-04',
      condition: 'Poor',
      language: 'IT',
      reverse: false,
      firstEdition: false,
      graded: false,
      medianPkn: 12.5,
      minPkn: 10,
      maxPkn: 14,
      soldQty: 1,
      listings: 1,
      sampleCount: 1,
      comments: ['whitening'],
    },
  );
});
