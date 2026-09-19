'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const handler = require('./marketplace-rails');

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

test('marketplace-rails requires id or ids', async () => {
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-rails',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 400);
});
