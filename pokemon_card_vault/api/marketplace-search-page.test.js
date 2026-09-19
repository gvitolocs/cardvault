const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler } = require('./marketplace-search-page');

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

test('search-page BFF pages Meili rows and returns product facets', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows,
    rowsForCards: async ({ query, limit, offset, lightHydrate }) => {
      assert.equal(query, 'Charizard');
      assert.equal(offset, 0);
      assert.equal(limit, 101);
      assert.equal(lightHydrate, true);
      return Array.from({ length: 101 }, (_, index) => ({
        card_id: 1000 + index,
        name: `Charizard ${index}`,
        set_name: 'Base Set',
        card_number: `${index}/102`,
        image_url: `https://cdn.pokoin.com/${500 + index}_charizard.jpg`,
        preview_image_url: `https://cdn.pokoin.com/previews/${500 + index}_charizard.jpg`,
      }));
    },
    productFacetRows: async () => ([
      { productType: 'card', count: 80 },
      { productType: 'booster_box', count: 2 },
    ]),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-search-page?query=Charizard',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cards.length, 100);
  assert.equal(res.body.hasMore, true);
  assert.equal(res.body.cards[0].gridImageUrl.includes('/previews/'), false);
  assert.equal(res.body.facets.products[0].productType, 'card');
});

test('search-page overlays cheapest_homepage_cache_blueprint onto identity rows', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows.map((row) => (
      String(row.card_id) === '259390'
        ? { ...row, lowest_price_pkn: 228, listed_quantity: 85, has_cardtrader_listing: true }
        : row
    )),
    rowsForCards: async () => ([{
      card_id: 259390,
      ct_id: 129695,
      name: 'Spiritomb',
      set_name: 'Team Up',
      card_number: '89/181',
      image_url: 'https://cdn.pokoin.com/129695_spiritomb.jpg',
    }]),
    productFacetRows: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-search-page?query=Spiritomb%20Team%20Up&limit=4',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cards[0].price, 228);
  assert.equal(res.body.cards[0].hasCardTraderListing, true);
});

test('search-page stamps localized names for title language without replacing English identity', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows,
    marketplaceQuery: async () => ({ rows: [] }),
    attachTitleLanguageOnRows: async (rows) => rows.map((row) => ({
      ...row,
      localized_name: 'Camilla',
      localized_set: 'Prisma Lucente',
    })),
    rowsForCards: async ({ searchLanguage }) => {
      assert.equal(searchLanguage, 'it');
      return [{
        card_id: 1,
        name: 'Dawn',
        set_name: 'Ultra Prism',
        card_number: '129/156',
        image_url: 'https://cdn.pokoin.com/1_dawn.jpg',
      }];
    },
    productFacetRows: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-search-page?query=Dawn&search_language=it',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.cards[0].name, 'Dawn');
  assert.equal(res.body.cards[0].localized_name, 'Camilla');
  assert.equal(res.body.cards[0].localized_set, 'Prisma Lucente');
});

test('search-page returns the same-predicate total beside the page count', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows,
    rowsForCards: async ({ withTotal }) => {
      assert.equal(withTotal, true);
      return {
        rows: Array.from({ length: 3 }, (_, index) => ({
          card_id: 2000 + index,
          name: 'Pikachu GX',
          set_name: 'Team Up',
          card_number: `${index + 1}/181`,
          image_url: `https://cdn.pokoin.com/${index}_pikachu_gx.jpg`,
        })),
        total: 37,
      };
    },
    productFacetRows: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-search-page?query=pikachu%20gx&includeFacets=0',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.total, 37);
  assert.equal(res.body.count, 3);
  assert.equal(res.body.hasMore, false);
});

test('search-page keeps total null for bare-array row loads', async () => {
  const handler = createHandler({
    overlayCheapestOnRows: async (rows) => rows,
    rowsForCards: async () => ([{
      card_id: 1,
      name: 'Dawn',
      set_name: 'Ultra Prism',
      card_number: '129/156',
      image_url: 'https://cdn.pokoin.com/1_dawn.jpg',
    }]),
    productFacetRows: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-search-page?query=Dawn',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.total, null);
  assert.equal(res.body.count, 1);
});
