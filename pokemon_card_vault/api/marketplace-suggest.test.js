const assert = require('node:assert/strict');
const test = require('node:test');
const { mapMarketplaceMeiliDoc, meiliMarketplaceIndexSettings } = require('./_meili_document');
const { groupSuggestHits, capSuggestRows } = require('./_meili_suggest');
const { createHandler } = require('./marketplace-suggest');
const { resetExpansionNationalityCache } = require('./_expansion_nationality');
const { mapsFromRows, overlayTitleLanguageOnGroups } = require('./_catalog_title_language');

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

test('Meili marketplace documents include collector number, set, image, and canonical path', () => {
  const doc = mapMarketplaceMeiliDoc({
    card_id: 220962,
    language: 'en',
    name: 'Espurr',
    name_normalized: 'espurr',
    name_compact: 'espurr',
    set_name: 'XY',
    expansion_name: 'XY',
    card_number: '42/146',
    rarity: 'Common',
    cdn_image_url: 'https://cdn.pokoin.com/previews/110481_espurr.jpg',
    image_url: 'https://cdn.pokoin.com/110481_espurr.jpg',
    search_weight: 12,
    updated_at_epoch: 1,
  });
  assert.equal(doc.card_number, '42/146');
  assert.equal(doc.set_name, 'XY');
  assert.equal(doc.name_group, 'Espurr');
  assert.equal(doc.cdn_image_url, 'https://cdn.pokoin.com/110481_espurr.jpg');
  assert.match(doc.canonical_path, /\/marketplace\/en\/cards\/220962\//);
  assert.ok(meiliMarketplaceIndexSettings().searchableAttributes.includes('card_number'));
  assert.ok(meiliMarketplaceIndexSettings().searchableAttributes.includes('nicknames'));
  assert.deepEqual(doc.nicknames, []);
});

test('suggest groups printings by gameplay name', () => {
  const groups = groupSuggestHits([
    {
      card_id: '220962',
      name: 'Pikachu',
      name_group: 'Pikachu',
      set_name: 'Base Set',
      card_number: '58/102',
      cdn_image_url: 'https://cdn.pokoin.com/1_pikachu.jpg',
    },
    {
      card_id: '220964',
      name: 'Pikachu',
      name_group: 'Pikachu',
      set_name: 'Jungle',
      card_number: '60/64',
      cdn_image_url: 'https://cdn.pokoin.com/2_pikachu.jpg',
    },
    {
      card_id: '220966',
      name: 'Raichu',
      name_group: 'Raichu',
      set_name: 'Base Set',
      card_number: '14/102',
      cdn_image_url: 'https://cdn.pokoin.com/3_raichu.jpg',
    },
  ], 8);
  assert.equal(groups.length, 2);
  assert.equal(groups[0].name, 'Pikachu');
  assert.equal(groups[0].printings.length, 2);
  assert.equal(groups[1].name, 'Raichu');
  assert.match(groups[0].printings[0].href, /\/marketplace\/en\/cards\/220962\//);
});

test('suggest rows stamp single/card so the popup stops re-classifying at keystroke time', () => {
  const groups = groupSuggestHits([
    {
      card_id: '242634',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'Theme Deck & Blisters Exclusives',
      card_number: 'Non-Holo Theme Deck | 58/145',
      rarity: 'Card',
    },
    {
      card_id: '242636',
      name: 'Mimikyu Pin Collection',
      name_group: 'Mimikyu Pin Collection',
      set_name: 'Pokémon Products',
      card_number: '',
      rarity: 'Card',
    },
    {
      card_id: '242638',
      name: 'Mimikyu ex',
      name_group: 'Mimikyu ex',
      set_name: 'SV Black Star Promos',
      card_number: 'Jumbo Oversized | SVP 004',
      rarity: 'Card',
    },
  ], 8, 20, 'mimikyu');
  const byId = new Map(groups.flatMap((group) => group.printings).map((row) => [row.card_id, row]));
  assert.equal(byId.get('242634').item_kind, 'single');
  assert.equal(byId.get('242634').product_type, 'card');
  assert.equal(byId.get('242636').item_kind, undefined, 'sealed SKU has no n/m — no stamp');
  assert.equal(byId.get('242638').item_kind, undefined, 'jumbo label without n/m — no stamp');
});

test('suggest caps printings per gameplay name so the popup stays a picker', () => {
  const hits = Array.from({ length: 12 }, (_, index) => ({
    card_id: String(220962 + index * 2),
    name: 'Drowzee',
    name_group: 'Drowzee',
    set_name: `Set ${index}`,
    card_number: `${index}/198`,
  }));
  const groups = groupSuggestHits(hits, 8, 6);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].printings.length, 6);
});

test('suggest popup keeps 20 printing rows across groups', () => {
  const hits = [
    ...Array.from({ length: 12 }, (_, index) => ({
      card_id: String(10 + index),
      name: 'Pikachu',
      name_group: 'Pikachu',
      set_name: `Set ${index}`,
    })),
    ...Array.from({ length: 12 }, (_, index) => ({
      card_id: String(100 + index),
      name: 'Raichu',
      name_group: 'Raichu',
      set_name: `Set ${index}`,
    })),
  ];
  const groups = capSuggestRows(groupSuggestHits(hits, 20, 20), 20);
  const shown = groups.reduce((sum, group) => sum + group.printings.length, 0);
  assert.equal(shown, 20);
  assert.equal(groups[0].name, 'Pikachu');
  assert.equal(groups[0].printings.length, 12);
  assert.equal(groups[1].printings.length, 8);
});

test('GET /api/marketplace-suggest is Meili-only and does not fall back to SQL', async () => {
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    meiliMarketplaceSuggestHits: async (query, language, limit) => {
      assert.equal(query, 'pika');
      assert.equal(language, 'en');
      assert.ok(limit >= 12);
      return [{
        card_id: '10',
        name: 'Pikachu',
        name_group: 'Pikachu',
        set_name: 'Base Set',
        card_number: '58/102',
        rarity: 'Common',
        cdn_image_url: 'https://cdn.pokoin.com/10_pikachu.jpg',
        canonical_path: '/marketplace/en/cards/10/common-pikachu-58-102-base-set',
      }];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=pika&limit=8',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.groups.length, 1);
  assert.equal(res.body.groups[0].printings[0].id, '10');
  assert.match(res.headers['Cache-Control'], /s-maxage=30/);
});

test('GET /api/marketplace-suggest count is Meili estimatedTotalHits for all-print queries', async () => {
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    meiliMarketplaceSuggestHits: async () => ({
      estimatedTotalHits: 847,
      printFilterApplied: false,
      hits: [{
        card_id: '10',
        name: 'Pikachu',
        name_group: 'Pikachu',
        set_name: 'Base Set',
        card_number: '58/102',
        nationality: 'western',
      }],
    }),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=pikachu',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.shown, 1);
  assert.equal(res.body.count, 847);
});

test('GET /api/marketplace-suggest western count is the filtered universe, not global Meili hits', async () => {
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    attachExpansionNationality: async (groups) => groups,
    meiliMarketplaceSuggestHits: async (_q, _lang, _limit, options) => {
      assert.equal(options.printLanguage, 'western');
      return {
        estimatedTotalHits: 12,
        printFilterApplied: true,
        hits: [
          {
            card_id: '10',
            name: 'Pikachu',
            name_group: 'Pikachu',
            set_name: 'Base Set',
            card_number: '58/102',
            nationality: 'western',
          },
          {
            card_id: '11',
            name: 'Pikachu',
            name_group: 'Pikachu',
            set_name: 'Base Set',
            card_number: '58/102',
            nationality: 'western',
          },
        ],
      };
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=pikachu&print_language=western',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.printLanguage, 'western');
  assert.ok(res.body.groups.every((group) => (
    group.printings.every((row) => row.nationality === 'western')
  )));
  assert.equal(res.body.count, 12);
  assert.equal(res.body.globalCount, 12);
});

test('GET /api/marketplace-suggest defaults to 20 groups and over-fetches Meili hits', async () => {
  let requestedLimit = 0;
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    meiliMarketplaceSuggestHits: async (_query, _language, limit) => {
      requestedLimit = limit;
      return [];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=pi',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(requestedLimit, 96);
});

test('plain prefix mimik ranks Mimikyu ahead of Mimikyu GX and products', () => {
  const groups = groupSuggestHits([
    {
      card_id: '245152',
      name: 'Mimikyu GX',
      name_group: 'Mimikyu GX',
      set_name: 'Lost Thunder',
      card_number: '149/214',
      search_weight: 24,
    },
    {
      card_id: '209526',
      name: 'Mimikyu Pin Collection',
      name_group: 'Mimikyu Pin Collection',
      set_name: 'Pokémon Products',
      search_weight: 16,
    },
    {
      card_id: '226088',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'Cosmic Eclipse',
      card_number: '096/236',
      search_weight: 14,
    },
    {
      card_id: '413144',
      name: 'Mimikyu VMAX',
      name_group: 'Mimikyu VMAX',
      set_name: 'Brilliant Stars',
      card_number: '069/172',
      search_weight: 24,
    },
  ], 8, 6, 'mimik');
  assert.equal(groups[0].name, 'Mimikyu');
  assert.equal(groups[1].name, 'Mimikyu GX');
  assert.ok(groups.findIndex((group) => group.name === 'Mimikyu Pin Collection') > groups.findIndex((group) => group.name === 'Mimikyu GX'));
});

test('query with GX keeps Mimikyu GX ahead of base Mimikyu', () => {
  const groups = groupSuggestHits([
    {
      card_id: '226088',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      search_weight: 14,
    },
    {
      card_id: '245152',
      name: 'Mimikyu GX',
      name_group: 'Mimikyu GX',
      search_weight: 24,
    },
  ], 8, 6, 'mimikyu gx');
  assert.equal(groups[0].name, 'Mimikyu GX');
});

test('leftover g continues the card name GX, not set Guardians Rising', () => {
  const groups = groupSuggestHits([
    {
      card_id: '240800',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'Guardians Rising',
      card_number: '58/145',
      search_weight: 14,
    },
    {
      card_id: '245152',
      name: 'Mimikyu GX',
      name_group: 'Mimikyu GX',
      set_name: 'Lost Thunder',
      card_number: '149/214',
      search_weight: 24,
    },
    {
      card_id: '226088',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'Cosmic Eclipse',
      card_number: '096/236',
      search_weight: 14,
    },
    {
      card_id: '401604',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'GX Starter Decks',
      card_number: '051/131',
      search_weight: 14,
    },
  ], 8, 6, 'mimikyu g');
  assert.equal(groups[0].name, 'Mimikyu GX');
  const mimikyu = groups.find((group) => group.name === 'Mimikyu');
  assert.ok(mimikyu);
  assert.notEqual(mimikyu.printings[0].set, 'Guardians Rising');
});

test('leftover cl binds Call of Legends, not the first Palkia Meili hit', () => {
  const groups = groupSuggestHits([
    {
      card_id: '1',
      name: 'Palkia',
      name_group: 'Palkia',
      set_name: 'Surging Sparks',
      card_number: '136/191',
      search_weight: 20,
      _rankingScore: 0.92,
    },
    {
      card_id: '2',
      name: 'Palkia',
      name_group: 'Palkia',
      set_name: 'Theme Deck & Blisters Exclusives',
      card_number: '040/182',
      search_weight: 12,
      _rankingScore: 0.9,
    },
    {
      card_id: '3',
      name: 'Palkia',
      name_group: 'Palkia',
      set_name: 'Call of Legends',
      card_number: 'Holo Rare | 19/95',
      expansion_aliases: ['cl', 'col', 'call of legends'],
      search_weight: 14,
      _rankingScore: 0.84,
    },
  ], 8, 20, 'palkia cl');
  assert.equal(groups[0].name, 'Palkia');
  assert.equal(groups[0].printings[0].set, 'Call of Legends');
});

test('card nicknames rank the named printing first in suggest', () => {
  const groups = groupSuggestHits([
    {
      card_id: '1',
      name: 'Pikachu',
      name_group: 'Pikachu',
      search_weight: 20,
    },
    {
      card_id: '2',
      name: 'Umbreon VMAX',
      name_group: 'Umbreon VMAX',
      nicknames: ['Moonbreon'],
      set_name: 'Evolving Skies',
      card_number: '215/203',
      search_weight: 24,
    },
  ], 8, 6, 'moonbreon');
  assert.equal(groups[0].name, 'Umbreon VMAX');
});

test('GET /api/marketplace-suggest returns empty groups when Meili is down', async () => {
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    meiliMarketplaceSuggestHits: async () => {
      throw new Error('meili down');
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=pika',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body.groups, []);
  assert.equal(res.body.reason, 'meili_error');
});

test('same Meili score prefers western printings in the popup without exposing _rank', async () => {
  resetExpansionNationalityCache();
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    marketplaceDatabaseUrl: () => '',
    marketplaceQuery: async () => ({
      rows: [
        { name: 'Beginning Set', normalized_name: 'beginning set', nationality: 'japanese' },
        { name: 'Black & White', normalized_name: 'black white', nationality: 'western' },
      ],
    }),
    meiliMarketplaceSuggestHits: async () => ({
      estimatedTotalHits: 2,
      hits: [
        {
          card_id: 'jp1',
          name: 'Oshawott',
          name_group: 'Oshawott',
          set_name: 'Beginning Set',
          card_number: '1/1',
          _rankingScore: 0.9,
        },
        {
          card_id: 'eu1',
          name: 'Oshawott',
          name_group: 'Oshawott',
          set_name: 'Black & White',
          card_number: '2/2',
          _rankingScore: 0.9,
        },
      ],
    }),
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=oshaw',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.deepEqual(res.body.groups[0].printings.map((row) => row.id), ['eu1', 'jp1']);
  assert.equal(res.body.groups[0].printings[0]._rank, undefined);
  assert.equal(res.body.groups[0].printings[0].nationality, 'western');
});

test('GET /api/marketplace-suggest stamps Italian names when title language is it', async () => {
  const maps = mapsFromRows({
    names: [['Ace Trainer', 'Fantallenatori']],
    sets: [['Base Set', 'Set Base']],
    rarities: [['Rare', 'Rara']],
  });
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    marketplaceQuery: async () => ({ rows: [] }),
    attachExpansionNationality: async (groups) => groups,
    attachTitleLanguageOnGroups: async (groups) => overlayTitleLanguageOnGroups(groups, maps),
    meiliMarketplaceSuggestHits: async (_query, language) => {
      assert.equal(language, 'it');
      return [{
        card_id: '10',
        name: 'Ace Trainer',
        name_group: 'Ace Trainer',
        set_name: 'Base Set',
        rarity: 'Rare',
        card_number: '1/102',
      }];
    },
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=ace&search_language=it',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.groups[0].name, 'Ace Trainer');
  assert.equal(res.body.groups[0].localized_name, 'Fantallenatori');
  assert.equal(res.body.groups[0].printings[0].localized_name, 'Fantallenatori');
  assert.equal(res.body.groups[0].printings[0].localized_set, 'Set Base');
  assert.equal(res.body.groups[0].printings[0].localized_rarity, 'Rara');
});
