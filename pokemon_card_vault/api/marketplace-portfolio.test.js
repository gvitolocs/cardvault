'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler, _test } = require('./marketplace-portfolio');

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

test('portfolio drops CardTrader leftover image hosts', () => {
  assert.equal(_test.isCardtraderHost('https://www.cardtrader.com/images/blueprint/403301'), true);
  const row = _test.dropForeignImages({
    cdn_image_url: 'https://www.cardtrader.com/images/blueprint/403301',
    image_url: 'https://cdn.pokoin.com/riftbound/403301_yasuo.jpg',
  });
  assert.equal(row.cdn_image_url, '');
  assert.equal(row.image_url, 'https://cdn.pokoin.com/riftbound/403301_yasuo.jpg');
});

test('portfolio holdings are PKN and public card ids', () => {
  const payload = _test.payloadFromRows([
    {
      card_id: '806602',
      floor_pkn: 50,
      total_pkn: 150,
      qty: 3,
      listing_count: 2,
      catalog_name: 'Yasuo - Unforgiven',
      expansion_name: 'Origins',
      card_number: '001',
      cdn_image_url: 'https://cdn.pokoin.com/riftbound/403301_yasuo-unforgiven.jpg',
      canonical_path: '/marketplace/en/cards/806602/card-yasuo-unforgiven',
    },
  ], 'riftbound');
  assert.equal(payload.game, 'riftbound');
  assert.equal(payload.items[0].id, '806602');
  assert.equal(payload.items[0].pricePkn, 50);
  assert.equal(payload.items[0].totalPkn, 150);
  assert.equal(payload.totals.pkn, 150);
  assert.equal(payload.items[0].gridImageUrl.includes('cardtrader.com'), false);
  assert.match(payload.items[0].gridImageUrl, /cdn\.pokoin\.com|\/card-images\//);
});

test('portfolio BFF returns native holdings without USD', async () => {
  const handler = createHandler({
    loadPortfolio: async () => ([
      {
        card_id: '713832',
        floor_pkn: 20,
        total_pkn: 40,
        qty: 2,
        listing_count: 1,
        catalog_name: 'Mega Charizard X ex',
        expansion_name: 'Phantasmal Flames',
        cdn_image_url: 'https://cdn.pokoin.com/356916_mega-charizard-x-ex.jpg',
      },
    ]),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-portfolio',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.items[0].pricePkn, 20);
  assert.equal(res.body.totals.qty, 2);
  assert.equal(JSON.stringify(res.body).includes('usd'), false);
  assert.equal(JSON.stringify(res.body).includes('cardtrader.com'), false);
});

test('portfolio treats missing listings table as empty, not 500', () => {
  assert.equal(_test.isUndefinedTable({ code: '42P01', message: 'relation "public.marketplace_user_listings" does not exist' }), true);
});

test('satellite portfolio default limit covers Riftbound catalog', () => {
  assert.equal(_test.limitForGame('', 'riftbound'), 2000);
  assert.equal(_test.limitForGame('9000', 'riftbound'), 2500);
  assert.equal(_test.limitForGame('', 'pokemon'), 400);
});

test('catalog holding without ask still returns PKN fields and public id', () => {
  const payload = _test.payloadFromRows([
    {
      card_id: '806602',
      floor_pkn: 0,
      total_pkn: 0,
      qty: 1,
      listing_count: 0,
      catalog_name: 'Yasuo - Unforgiven',
      expansion_name: 'Promos',
      cdn_image_url: 'https://cdn.pokoin.com/riftbound/403301_yasuo-unforgiven.webp',
    },
  ], 'riftbound');
  assert.equal(payload.items[0].id, '806602');
  assert.equal(payload.items[0].pricePkn, 0);
  assert.equal(payload.items[0].source, 'catalog');
  assert.equal(payload.items[0].heroImageUrl.includes('cardtrader.com'), false);
  assert.match(payload.items[0].heroImageUrl, /riftbound\/403301_yasuo-unforgiven/);
});

test('portfolio BFF on riftbound host stays PKN', async () => {
  const handler = _test.createHandler({
    loadPortfolio: async ({ cardId }) => ([{
      card_id: cardId || '806602',
      floor_pkn: 10000,
      total_pkn: 10000,
      qty: 1,
      listing_count: 0,
      catalog_name: 'Yasuo - Unforgiven',
      expansion_name: 'Promos',
      cdn_image_url: 'https://cdn.pokoin.com/riftbound/403301_yasuo-unforgiven.webp',
    }]),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-portfolio?id=403301',
    headers: { host: 'riftbound.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.game, 'riftbound');
  assert.equal(res.body.items[0].pricePkn, 10000);
  assert.equal(JSON.stringify(res.body).includes('$'), false);
  assert.equal(JSON.stringify(res.body).includes('cardtrader.com'), false);
});
