const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler, slugify } = require('./marketplace-expansion-page');

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

test('expansion-page BFF lists cards for an expansionName', async () => {
  const handler = createHandler({
    rowsForExpansions: async ({ slug }) => {
      assert.equal(slug, 'mega-evolution');
      return [{
        name: 'Mega Evolution',
        slug: 'mega-evolution',
        cardCount: 188,
        symbolImageUrl: '',
      }];
    },
    snapshotForExpansion: async () => {
      throw new Error('snapshot should not run when expansionName is set');
    },
    rowsForVersions: async ({ expansionName, productType }) => {
      assert.equal(expansionName, 'Mega Evolution');
      assert.equal(productType, 'card');
      return [{
        card_id: 703382,
        ct_id: 351691,
        name: 'Mega Lucario ex',
        expansion_name: 'Mega Evolution',
        expansion_number: '028/132',
        image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
        preview_image_url: 'https://cdn.pokoin.com/previews/351691_mega-lucario-ex.jpg',
      }];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?expansionName=Mega%20Evolution&productType=card',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.expansion.name, 'Mega Evolution');
  assert.equal(res.body.cards.length, 1);
  assert.equal(res.body.cards[0].heroImageUrl, '/card-images/703382_mega-lucario-ex.jpg');
});

test('expansion-page hasMore is true when SQL returns more than one page', async () => {
  let seen = null;
  const handler = createHandler({
    rowsForExpansions: async () => [{
      name: 'Dark Explorers',
      slug: 'dark-explorers',
      cardCount: 111,
      symbolImageUrl: '',
    }],
    readSetCards: async ({ setName, limit, offset }) => {
      seen = { setName, limit, offset };
      return Array.from({ length: limit }, (_, index) => ({
        card_id: 227370 + index,
        ct_id: 113685 + index,
        name: `Card ${index}`,
        set_name: setName,
        expansion_name: setName,
        card_number: `${index + 1}/108`,
        image_url: 'https://cdn.pokoin.com/dark-explorers.jpg',
      }));
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?expansionName=Dark%20Explorers&productType=card&limit=200',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(seen.limit, 201);
  assert.equal(seen.offset, 0);
  assert.equal(res.body.cards.length, 200);
  assert.equal(res.body.hasMore, true);
  assert.equal(res.body.limit, 200);
});

test('expansion-page hasMore is false on a short last page', async () => {
  const handler = createHandler({
    rowsForExpansions: async () => [{
      name: 'Dark Explorers',
      slug: 'dark-explorers',
      cardCount: 111,
      symbolImageUrl: '',
    }],
    readSetCards: async ({ limit, offset }) => {
      assert.equal(offset, 96);
      return Array.from({ length: 15 }, (_, index) => ({
        card_id: 227000 + index,
        ct_id: 113000 + index,
        name: `Card ${index}`,
        set_name: 'Dark Explorers',
        image_url: 'https://cdn.pokoin.com/dark-explorers.jpg',
      }));
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?expansionName=Dark%20Explorers&productType=card&limit=48&offset=96',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cards.length, 15);
  assert.equal(res.body.hasMore, false);
});

test('expansion-page total is the catalog count, not the page size', async () => {
  const handler = createHandler({
    rowsForExpansions: async () => [{
      name: 'White Flare',
      slug: 'white-flare',
      cardCount: 0,
      symbolImageUrl: '',
    }],
    readSetCardCount: async (setName) => {
      assert.equal(setName, 'White Flare');
      return 173;
    },
    readSetCards: async ({ limit }) => Array.from({ length: limit }, (_, index) => ({
      card_id: 800000 + index,
      ct_id: 400000 + index,
      name: `Card ${index}`,
      set_name: 'White Flare',
      image_url: 'https://cdn.pokoin.com/white-flare.jpg',
    })),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?slug=white-flare&productType=card&limit=48&offset=0',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.cards.length, 48);
  assert.equal(res.body.count, 48);
  assert.equal(res.body.total, 173);
  assert.equal(res.body.expansion.cardCount, 173);
  assert.equal(res.body.hasMore, true);
});

test('expansion-page returns expansion.nationality from the catalog', async () => {
  const handler = createHandler({
    rowsForExpansions: async () => [{
      name: 'World Champions Pack',
      slug: 'world-champions-pack',
      cardCount: 108,
      nationality: 'japanese',
    }],
    readSetCards: async ({ limit }) => Array.from({ length: Math.min(limit, 1) }, () => ({
      card_id: 400000,
      ct_id: 200000,
      name: 'Seedot',
      set_name: 'World Champions Pack',
      image_url: 'https://cdn.pokoin.com/wcp-seedot.jpg',
    })),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?slug=world-champions-pack&productType=card&limit=48',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.expansion.name, 'World Champions Pack');
  assert.equal(res.body.expansion.nationality, 'japanese');
  assert.equal(res.body.expansion.cardCount, 108);
});

test('slugify expansion names', () => {
  assert.equal(slugify('Mega Evolution'), 'mega-evolution');
  assert.equal(slugify('Scarlet & Violet'), 'scarlet-and-violet');
  assert.equal(slugify('Play! Pokémon Prize Pack Series'), 'play-pokemon-prize-pack-series');
});

test('expansion-page lists satellite sets from set counts, not Pokemon expansions', async () => {
  let pokemonListCalled = false;
  const handler = createHandler({
    rowsForExpansions: async () => {
      pokemonListCalled = true;
      return [{ name: '10th Movie Commemoration Set', slug: '10th-movie-commemoration-set' }];
    },
    listExpansions: async () => [{
      name: 'Spiritforged',
      slug: 'spiritforged',
      cardCount: 298,
    }],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-expansion-page?limit=20&game=riftbound',
    headers: { host: 'riftbound.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.game, 'riftbound');
  assert.equal(res.body.expansions[0].name, 'Spiritforged');
  assert.equal(pokemonListCalled, false);
});
