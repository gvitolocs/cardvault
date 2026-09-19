'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const handler = require('./marketplace-card-tiles');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    end() {
      return this;
    },
  };
  return res;
}

test('marketplace-card-tiles returns pi source for empty ids', async () => {
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-tiles?ids=',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.source, 'pi');
  assert.deepEqual(res.body.cards, []);
});

test('tile summaries carry the compact theme pack (vt)', async () => {
  const rails = require('./_marketplace_rails');
  const sql = require('./_marketplace_react_sql');
  const PACKED = 'v1'
    + '1c0705' + '2c1512' + '3d211c' + '8a3a28' + '7a463a' + '452a24' + '8a3f2c';
  const originalReadTiles = rails.readTiles;
  const originalPacks = sql.readCardThemePacks;
  rails.readTiles = async () => [{
    id: 251820,
    card_id: 251820,
    ct_id: 125910,
    name: 'Torchic',
  }];
  sql.readCardThemePacks = async () => new Map([['251820', PACKED]]);
  try {
    const res = mockRes();
    await handler({
      method: 'GET',
      url: '/api/marketplace-card-tiles?ids=251820',
      headers: { host: 'api.pokoin.com' },
    }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.cards[0].vt, PACKED);
    // Cards without a pack stay untouched (no neutral vt noise).
    sql.readCardThemePacks = async () => new Map();
    const bare = mockRes();
    await handler({
      method: 'GET',
      url: '/api/marketplace-card-tiles?ids=251820',
      headers: { host: 'api.pokoin.com' },
    }, bare);
    assert.equal(bare.body.cards[0].vt, undefined);
  } finally {
    rails.readTiles = originalReadTiles;
    sql.readCardThemePacks = originalPacks;
  }
});

test('withThemePacks never fails a summary when the theme lookup throws', async () => {
  const { withThemePacks } = require('./_marketplace_rails');
  const cards = [{ id: 251820, card_id: 251820 }];
  const out = await withThemePacks(cards, {
    readCardThemePacks: async () => {
      throw new Error('db down');
    },
  });
  assert.deepEqual(out, cards);
  assert.deepEqual(await withThemePacks([], { readCardThemePacks: async () => new Map() }), []);
});
