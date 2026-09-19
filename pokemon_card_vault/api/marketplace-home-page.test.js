'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler } = require('./marketplace-home-page');

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

test('home-page BFF returns React cards and refuses preview heroes', async () => {
  const handler = createHandler({
    loadHomeSnapshot: async () => ({
      cards: [{
        id: '703382',
        card_id: '703382',
        name: 'Mega Lucario ex',
        gridImageUrl: '/card-images/351691_mega-lucario-ex.jpg',
        heroImageUrl: '/card-images/351691_mega-lucario-ex.jpg',
        previewImageUrl: '/card-images/previews/351691_mega-lucario-ex.jpg',
        isMarketAvailable: true,
      }],
      sections: {
        newArrivalIds: ['703382'],
        featuredIds: ['703382'],
        bestSellerIds: ['703382'],
        recentlySeenIds: [],
        spotlightIds: ['703382'],
      },
    }),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-home-page',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cards[0].id, '703382');
  assert.equal(res.body.cards[0].gridImageUrl.includes('/previews/'), false);
  assert.equal(res.body.sections.newArrivalIds[0], '703382');
  assert.match(res.headers['Cache-Control'], /s-maxage/);
});

test('home-page merges recentCardIds as a private response', async () => {
  const handler = createHandler({
    loadHomeSnapshot: async () => ({
      cards: [{
        id: '703382',
        name: 'Mega Lucario ex',
        gridImageUrl: '/card-images/351691_mega-lucario-ex.jpg',
      }],
      sections: {
        newArrivalIds: ['703382'],
        featuredIds: [],
        bestSellerIds: [],
        recentlySeenIds: [],
        spotlightIds: [],
      },
    }),
    loadCardsByIds: async (ids) => {
      assert.deepEqual(ids, ['587148']);
      return [{
        id: '587148',
        name: 'Magcargo GX',
        gridImageUrl: '/card-images/293574_magcargo-gx.jpg',
      }];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-home-page?recentCardIds=587148',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.sections.recentlySeenIds[0], '587148');
  assert.equal(res.body.cards.some((card) => card.id === '587148'), true);
  assert.match(res.headers['Cache-Control'], /no-store/);
});
