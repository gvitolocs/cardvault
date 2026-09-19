const assert = require('node:assert/strict');
const test = require('node:test');
const { createHandler } = require('./marketplace-card-page');

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

test('card-page BFF composes card, offers, cheapest, and refuses preview as hero', async () => {
  const handler = createHandler({
    rowsForVersions: async ({ cardId, sameAsCardId }) => {
      if (sameAsCardId) {
        return [{
          card_id: 703384,
          name: 'Mega Lucario ex',
          expansion_name: 'Mega Evolution',
          expansion_number: '125/132',
          image_url: 'https://cdn.pokoin.com/351692_mega-lucario-ex.jpg',
          preview_image_url: 'https://cdn.pokoin.com/previews/351692_mega-lucario-ex.jpg',
        }];
      }
      assert.equal(cardId, '703382');
      return [{
        card_id: 703382,
        ct_id: 351691,
        name: 'Mega Lucario ex',
        expansion_name: 'Mega Evolution',
        expansion_number: '028/132',
        rarity: 'Double Rare',
        image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
        preview_image_url: 'https://cdn.pokoin.com/previews/351691_mega-lucario-ex.jpg',
        homepage_image_url: 'https://cdn.pokoin.com/previews/351691_mega-lucario-ex.jpg',
        canonical_path: '/marketplace/en/cards/703382/card-mega-lucario-ex',
        artist: 'aky CG Works',
        emoji: '🥊 💥 💎',
        listed_quantity: 3,
        has_cardtrader_listing: true,
        lowest_price_pkn: 12.5,
      }];
    },
    canonicalCardUrlForLookup: async () => ({
      cardId: '703382',
      canonicalPath: '/marketplace/en/cards/703382/card-mega-lucario-ex-028-132-mega-evolution',
    }),
    readCheapestPrices: async () => ([{
      cardId: '703382',
      pricePkn: 12.5,
      available: true,
      cardtrader: { available: true },
    }]),
    readOffers: async (cardId) => {
      assert.equal(cardId, '703382');
      return [{ id: 'offer-1', cardId, pricePkn: 12.5, quantityAvailable: 2 }];
    },
    readSales: async () => {
      throw new Error('sales should not run by default');
    },
  });

  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=703382&includeSameAs=1&includeOffers=1',
    headers: { host: 'api.pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.card.id, '703382');
  assert.equal(res.body.card.ct_id, undefined);
  assert.equal(res.body.card.heroImageUrl, '/card-images/703382_mega-lucario-ex.jpg');
  assert.equal(res.body.card.gridImageUrl.includes('/previews/'), false);
  assert.equal(res.body.offers.length, 1);
  assert.equal(res.body.sales.length, 0);
  assert.equal(res.body.sameAs[0].id, '703384');
  assert.match(res.body.canonicalPath, /703382/);
  assert.equal(res.body.card.isMarketAvailable, true);
  assert.equal(res.body.card.artist, 'aky CG Works');
  assert.equal(res.body.artist.name, 'aky CG Works');
  assert.equal(res.body.card.emoji, '🥊 💥 💎');
});

test('card-page puts the CLIP version on the payload used at desk load', async () => {
  const handler = createHandler({
    rowsForVersions: async () => [{
      card_id: 802368,
      ct_id: 401184,
      name: 'Quaxly',
      expansion_name: '30th Anniversary Celebration: First Partner Illustration Collection',
      expansion_number: '027/30th-P',
      version: 'v791574',
      image_url: 'https://cdn.pokoin.com/401184_quaxly.jpg',
    }],
    readSetSiblings: async () => ([
      {
        card_id: 791574,
        name: 'Quaxly',
        expansion_name: 'MEP Black Star Promos',
        expansion_number: 'MEP 063',
        version: 'v791574',
        image_url: 'https://cdn.pokoin.com/395787_quaxly.jpg',
      },
      {
        card_id: 802368,
        name: 'Quaxly',
        expansion_name: '30th Anniversary Celebration: First Partner Illustration Collection',
        expansion_number: '027/30th-P',
        version: 'v791574',
        image_url: 'https://cdn.pokoin.com/401184_quaxly.jpg',
      },
    ]),
    readVersionSetMeta: async (cardId) => {
      assert.equal(cardId, '802368');
      return { version: 'v791574', member_count: 3 };
    },
    canonicalCardUrlForLookup: async () => ({
      canonicalPath: '/marketplace/en/cards/802368/card-quaxly',
    }),
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=802368',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.version, 'v791574');
  assert.equal(res.body.card.version, 'v791574');
  assert.equal(res.body.versionCount, 3);
  assert.equal(res.body.versions.length, 2);
  assert.equal(res.body.versions[0].version, 'v791574');
});

test('card-page rarities are same-name same-set, not CLIP versions', async () => {
  const handler = createHandler({
    readCardRow: async () => ({
      card_id: 806356,
      name: 'Mega Rayquaza ex',
      set_name: 'Storm Emeralda',
      card_number: 'Full-Art | 095/076',
      image_url: 'https://cdn.pokoin.com/806356.jpg',
      version: 'v806356',
    }),
    readSetSiblings: async (row) => [row],
    readNameSetSiblings: async () => ([
      {
        card_id: 806172,
        name: 'Mega Rayquaza ex',
        set_name: 'Storm Emeralda',
        card_number: 'Ultra Rare | 058/076',
        image_url: 'https://cdn.pokoin.com/806172.jpg',
      },
      {
        card_id: 806356,
        name: 'Mega Rayquaza ex',
        set_name: 'Storm Emeralda',
        card_number: 'Full-Art | 095/076',
        image_url: 'https://cdn.pokoin.com/806356.jpg',
      },
      {
        card_id: 806056,
        name: 'Mega Rayquaza ex',
        set_name: 'Storm Emeralda',
        card_number: 'Special Illustration Rare | 110/076',
        image_url: 'https://cdn.pokoin.com/806056.jpg',
      },
      {
        card_id: 806390,
        name: 'Mega Rayquaza ex',
        set_name: 'Storm Emeralda',
        card_number: 'Gold Secret Rare | 113/076',
        image_url: 'https://cdn.pokoin.com/806390.jpg',
      },
    ]),
    readVersionSetMeta: async () => ({ version: 'v806356', member_count: 1 }),
    canonicalCardUrlForLookup: async () => ({
      canonicalPath: '/marketplace/en/cards/806356/card-mega-rayquaza-ex',
    }),
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=806356',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.versions.length, 1);
  assert.equal(res.body.versionCount, 1);
  assert.equal(res.body.rarities.length, 4);
  assert.deepEqual(res.body.rarities.map((row) => row.id), ['806172', '806356', '806056', '806390']);
});

test('card-page skips sameAs unless includeSameAs=1', async () => {
  const handler = createHandler({
    rowsForVersions: async ({ sameAsCardId }) => {
      if (sameAsCardId) {
        throw new Error('sameAs should not run by default');
      }
      return [{
        card_id: 703382,
        ct_id: 351691,
        name: 'Mega Lucario ex',
        expansion_name: 'Mega Evolution',
        image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
      }];
    },
    canonicalCardUrlForLookup: async () => ({ canonicalPath: '/marketplace/en/cards/703382/card-mega-lucario-ex' }),
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=703382',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.sameAs.length, 0);
  assert.deepEqual(res.body.neighbors, { prev: [], next: [] });
});

test('card-page attaches wrapping set neighbors', async () => {
  const handler = createHandler({
    readCardRow: async () => ({
      card_id: 227370,
      ct_id: 113685,
      name: 'Bulbasaur',
      set_name: 'Dark Explorers',
      card_number: '1/108',
      image_url: 'https://cdn.pokoin.com/227370_bulbasaur.jpg',
    }),
    readSetSiblings: async (row) => [row],
    readSetNeighbors: async (row) => {
      assert.equal(String(row.card_id), '227370');
      return {
        prev: [{
          card_id: 227782,
          name: 'Pokémon Catcher',
          set_name: 'Dark Explorers',
          card_number: '111/108',
          image_url: 'https://cdn.pokoin.com/227782_catcher.jpg',
          canonical_path: '/marketplace/en/cards/227782/card-pokemon-catcher',
        }],
        next: [{
          card_id: 227374,
          name: 'Ivysaur',
          set_name: 'Dark Explorers',
          card_number: '2/108',
          image_url: 'https://cdn.pokoin.com/227374_ivysaur.jpg',
          canonical_path: '/marketplace/en/cards/227374/card-ivysaur',
        }],
      };
    },
    canonicalCardUrlForLookup: async () => ({
      canonicalPath: '/marketplace/en/cards/227370/card-bulbasaur-1-108-dark-explorers',
    }),
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=227370',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.neighbors.prev[0].id, '227782');
  assert.equal(res.body.neighbors.next[0].id, '227374');
  assert.equal(res.body.neighbors.next[0].number, '2/108');
});

test('set neighbors, rarities, and CLIP versions overlay cheapest_homepage_cache_blueprint', () => {
  const source = require('node:fs').readFileSync(
    require('node:path').join(__dirname, 'marketplace-card-page.js'),
    'utf8',
  );
  assert.match(source, /readCheapestMap\(ids, blueprints\)/);
  assert.match(source, /overlayCheapestOnRows\(rows\)/);
  assert.match(source, /readSetSiblings: async \(row\) => \{[\s\S]*overlayCheapestOnRows\(rows\)/);
  assert.doesNotMatch(source, /emptyCheap/);
});

test('card-page requires a public cardId', async () => {
  const handler = createHandler({
    rowsForVersions: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 400);
});

test('visualTheme rides the card-page payload next to card metadata', async () => {
  const theme = {
    version: 'v1',
    artworkShade: '#b52a2a',
    hue: 26.085,
    chroma: 0.176,
    background: '#1a0505',
    surface: '#2a1210',
    surfaceRaised: '#3a1e1a',
    hero: '#7c2f24',
    heroBorder: '#69403a',
    border: '#412725',
    tint: '#7c3428',
  };
  const handler = createHandler({
    readCardRow: async () => ({
      card_id: 703382,
      ct_id: 351691,
      name: 'Mega Lucario ex',
      expansion_name: 'Mega Evolution',
      expansion_number: '028/132',
      image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
      visual_theme: theme,
    }),
    readSetSiblings: async () => [],
    canonicalCardUrlForLookup: async () => null,
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=703382',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body.visualTheme, theme);
});

test('card-page serves a null visualTheme when the row has none', async () => {
  const handler = createHandler({
    readCardRow: async () => ({
      card_id: 703382,
      ct_id: 351691,
      name: 'Mega Lucario ex',
      expansion_name: 'Mega Evolution',
      expansion_number: '028/132',
      image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
    }),
    readSetSiblings: async () => [],
    canonicalCardUrlForLookup: async () => null,
    readCheapestPrices: async () => [],
    readOffers: async () => [],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-card-page?cardId=703382',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.visualTheme, null);
});

test('production readCardRow derives the theme from the current shade + identity', () => {
  const source = require('node:fs').readFileSync(
    require('node:path').join(__dirname, 'marketplace-card-page.js'),
    'utf8',
  );
  assert.match(source, /sql\.readArtShadeRows\(\[row\.ct_id\]\)/);
  assert.match(source, /sql\.readVisualThemes\(\[row\.ct_id\]\)/);
  assert.match(
    source,
    /visualThemeForShade\(\s*themes\.get\(Number\(row\.ct_id\)\),\s*artShade,\s*String\(shadeRow\.artwork_identity \|\| ''\),?\s*\)/,
  );
});
