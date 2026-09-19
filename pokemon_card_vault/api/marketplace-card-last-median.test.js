const assert = require('node:assert/strict');
const test = require('node:test');

const { lastMedianPayload } = require('./marketplace-card-sales');
const { cleanCardId, uniqueCardIds } = require('./marketplace-card-last-median');

test('lastMedianPayload keeps the latest daily median in PKN', () => {
  assert.deepEqual(
    lastMedianPayload('757880', { day: '2026-09-05', median_pkn: 866.4 }),
    {
      card_id: '757880',
      day: '2026-09-05',
      median_pkn: 866.4,
      sample_count: null,
      currency: 'PKN',
      source: 'cardtrader_removed_sale',
      condition: null,
      language: null,
      reverse: null,
      firstEdition: null,
      graded: null,
    },
  );
  assert.equal(lastMedianPayload('757880', null).median_pkn, null);
  assert.equal(lastMedianPayload('757880', { day: '2026-09-05', median_pkn: 866.4 }, { condition: 'NM', language: 'EN' }).condition, 'NM');
  assert.equal(lastMedianPayload('757880', { day: '2026-09-05', median_pkn: 866.4 }, { firstEdition: '1' }).firstEdition, true);
  assert.equal(lastMedianPayload('757880', { day: '2026-09-05', median_pkn: 866.4, listings: 9 }).sample_count, 9);
});

test('last-median uniqueCardIds accepts cardId or a bounded cardIds list', () => {
  assert.equal(cleanCardId('757880'), '757880');
  assert.equal(cleanCardId('nope'), '');
  assert.deepEqual(
    uniqueCardIds({
      url: '/api/marketplace-card-last-median?cardId=757880&cardIds=757880,720194,abc',
      headers: { host: 'pokoin.com' },
    }),
    ['757880', '720194'],
  );
});

test('Oracle last-median follows the same stored daily slice as the sales graph', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(path.join(__dirname, 'marketplace-card-sales.js'), 'utf8');
  assert.match(source, /async function readOracleLastMedian/);
  assert.match(source, /series.lastDay/);
  assert.match(source, /series.lastMedianPkn/);
  assert.match(source, /from public\.cardtrader_sold_daily/);
});

test('last-median handler requires cardId', async () => {
  const handler = require('./marketplace-card-last-median');
  const res = {
    headers: {},
    statusCode: 0,
    body: null,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    end() {
      return this;
    },
  };
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-last-median',
    headers: { host: 'pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'cardId is required.');
});
