'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler } = require('./cardtrader-redirect');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    ended: false,
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
      this.ended = true;
      return this;
    },
  };
  return res;
}

test('public One Piece id 818358 redirects to leftover 409179', async () => {
  const handler = createHandler({
    catalogIdsFor: async (id) => {
      assert.equal(id, '818358');
      return { cardId: '818358', ctId: '409179', name: 'Sanji' };
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/cardtrader-redirect?id=818358&game=one_piece',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 302);
  assert.equal(res.headers.Location, 'https://www.cardtrader.com/en/cards/409179');
});

test('leftover Mew 274416 stays 274416 and is not halved', async () => {
  const handler = createHandler({
    catalogIdsFor: async (id) => {
      assert.equal(id, '274416');
      return { cardId: '548832', ctId: '274416', name: 'Mew ex' };
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/cardtrader-redirect?id=274416',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.headers.Location, 'https://www.cardtrader.com/en/cards/274416');
});

test('public Mew 548832 maps to leftover 274416', async () => {
  const handler = createHandler({
    catalogIdsFor: async (id) => {
      assert.equal(id, '548832');
      return { cardId: '548832', ctId: '274416', name: 'Mew ex' };
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/cardtrader-redirect?id=548832&format=json',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ct_id, '274416');
  assert.equal(res.body.url, 'https://www.cardtrader.com/en/cards/274416');
});

test('blueprintId leftover wins over public id without dividing', async () => {
  const handler = createHandler({
    catalogIdsFor: async () => {
      throw new Error('lookup should not run when blueprintId is distinct');
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/cardtrader-redirect?id=818358&blueprintId=409179',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.headers.Location, 'https://www.cardtrader.com/en/cards/409179');
});
