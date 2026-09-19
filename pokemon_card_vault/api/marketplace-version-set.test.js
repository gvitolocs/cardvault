'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler, PRINTING_SQL } = require('./marketplace-version-set');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    writableEnded: false,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
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

test('version-set SQL reads member_count from pokoin_version_sets, not a sibling array', () => {
  assert.match(PRINTING_SQL, /pokoin_version_sets/);
  assert.match(PRINTING_SQL, /member_count/);
  assert.match(PRINTING_SQL, /c\.version =/);
  assert.doesNotMatch(PRINTING_SQL, /bigint\[\]/);
});

test('version-set API returns count from member_count and every printing of the key', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows,
    readVersionPrintings: async (cardId) => {
      assert.equal(cardId, '540696');
      return [
        {
          card_id: 540696,
          ct_id: 270348,
          name: 'Wo-Chien ex',
          set_name: 'Shiny Treasure ex',
          card_number: 'Gold Secret Rare | 355/190',
          version: 'v540696',
          nationality: 'japanese',
          member_count: 3,
          cdn_image_url: 'https://cdn.pokoin.com/270348_wo-chien-ex.jpg',
        },
        {
          card_id: 548848,
          ct_id: 274424,
          name: 'Wo-Chien ex',
          set_name: 'Paldean Fates',
          card_number: 'Gold Secret Rare | 240/091',
          version: 'v540696',
          nationality: 'western',
          member_count: 3,
          cdn_image_url: 'https://cdn.pokoin.com/274424_wo-chien-ex.jpg',
        },
        {
          card_id: 722606,
          name: 'Wo-Chien ex',
          set_name: 'CSVL2: Travel Special Pack',
          card_number: 'CSVL2C | Gold Secret Rare 129/052',
          version: 'v540696',
          nationality: 'chinese',
          member_count: 3,
        },
      ];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-version-set?cardId=540696',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.version, 'v540696');
  assert.equal(res.body.versionCount, 3);
  assert.equal(res.body.printings.length, 3);
  assert.equal(res.body.printings[0].nationality, 'japanese');
  assert.equal(res.body.printings[1].set, 'Paldean Fates');
});

test('version-set printings include listed cheapest PKN from the cache overlay', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows.map((row) => (
      Number(row.card_id) === 540696
        ? { ...row, lowest_price_pkn: 400, listed_quantity: 12, has_cardtrader_listing: true }
        : row
    )),
    readVersionPrintings: async () => ([{
      card_id: 540696,
      ct_id: 270348,
      name: 'Wo-Chien ex',
      set_name: 'Shiny Treasure ex',
      card_number: 'Gold Secret Rare | 355/190',
      version: 'v540696',
      nationality: 'japanese',
      member_count: 1,
      cdn_image_url: 'https://cdn.pokoin.com/270348_wo-chien-ex.jpg',
    }]),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-version-set?cardId=540696',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.printings[0].price, 400);
});
