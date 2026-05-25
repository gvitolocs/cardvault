const assert = require('node:assert/strict');
const test = require('node:test');

const db = require('./_marketplace_db');
const handler = require('./marketplace-event');

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    end() {
      return this;
    },
  };
}

test('marketplace search event records aggregate predictive chunks without raw query table writes', async () => {
  const calls = [];
  const originalQuery = db.marketplaceQuery;
  db.marketplaceQuery = async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [] };
  };
  try {
    const req = {
      method: 'POST',
      headers: {},
      body: {
        cardId: 25,
        eventType: 'search',
        source: 'marketplace_search',
        metadata: {
          query: 'Pikchu',
          language: 'en',
          resultRank: 1,
          resultCount: 20,
        },
      },
    };
    const res = responseRecorder();
    await handler(req, res);

    assert.equal(res.statusCode, 204);
    assert.equal(calls.length, 3);
    assert.match(calls[0].sql, /marketplace_card_events/);
    assert.match(calls[1].sql, /record_marketplace_query_chunks/);
    assert.deepEqual(calls[1].values, ['Pikchu', 'en', 'search', 2]);
    assert.match(calls[2].sql, /refresh_marketplace_hot_blueprints/);
  } finally {
    db.marketplaceQuery = originalQuery;
  }
});

