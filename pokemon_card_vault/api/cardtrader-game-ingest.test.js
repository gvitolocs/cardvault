'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const handler = require('./cardtrader-game-ingest');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    writableEnded: false,
    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      this.writableEnded = true;
      return this;
    },
    end() {
      this.writableEnded = true;
      return this;
    },
  };
  return res;
}

test('Pi pokemon API name cannot serve game ingest', async () => {
  const previous = process.env.POKOIN_API_SERVICE_NAME;
  process.env.POKOIN_API_SERVICE_NAME = 'pokoin-oracle-api';
  try {
    const res = mockRes();
    await handler({ method: 'GET', url: '/api/ingest', headers: {}, query: {}, params: {} }, res);
    assert.equal(res.statusCode, 404);
    assert.equal(res.body.code, 'POKEMON_STAYS_ON_PI');
  } finally {
    if (previous == null) delete process.env.POKOIN_API_SERVICE_NAME;
    else process.env.POKOIN_API_SERVICE_NAME = previous;
  }
});

test('ingest list omits pokemon', async () => {
  const previous = process.env.POKOIN_API_SERVICE_NAME;
  process.env.POKOIN_API_SERVICE_NAME = 'cardtrader-game-ingest-api';
  try {
    const res = mockRes();
    await handler({ method: 'GET', url: '/api/ingest', headers: {}, query: {}, params: {} }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.pokemon, 'pi');
    assert.equal(res.body.writer, 'nezopt-15t');
    const ids = res.body.games.map((game) => game.id);
    assert.equal(ids.includes('pokemon'), false);
    assert.equal(ids.includes('magic'), true);
    assert.equal(ids.includes('yugioh'), true);
    assert.equal(ids.includes('one_piece'), true);
  } finally {
    if (previous == null) delete process.env.POKOIN_API_SERVICE_NAME;
    else process.env.POKOIN_API_SERVICE_NAME = previous;
  }
});

test('pokemon path on ingest API is 404', async () => {
  const previous = process.env.POKOIN_API_SERVICE_NAME;
  process.env.POKOIN_API_SERVICE_NAME = 'cardtrader-game-ingest-api';
  try {
    const res = mockRes();
    await handler({
      method: 'GET',
      url: '/api/ingest/pokemon',
      headers: {},
      query: {},
      params: { game: 'pokemon' },
    }, res);
    assert.equal(res.statusCode, 404);
    assert.equal(res.body.code, 'POKEMON_STAYS_ON_PI');
  } finally {
    if (previous == null) delete process.env.POKOIN_API_SERVICE_NAME;
    else process.env.POKOIN_API_SERVICE_NAME = previous;
  }
});
