const assert = require('node:assert/strict');
const test = require('node:test');
const {
  buildExtensionSearchTerm,
  cleanExtensionQuery,
  isIllustratorCredit,
  marketplacePathForRow,
} = require('./extension-card-search');

test('extension search builds query from scraped structured card fields', () => {
  const result = buildExtensionSearchTerm({
    name: '  Pikachu  ',
    collectorNumber: '  025 / 165 ',
    expansion: 'Pokemon 151',
    rarity: 'Illustration Rare',
  });

  assert.equal(result.searchTerm, 'Pikachu 025 / 165 Pokemon 151 Illustration Rare');
  assert.equal(result.source, 'structured_fields');
  assert.deepEqual(result.parts, {
    name: 'Pikachu',
    collectorNumber: '025 / 165',
    expansion: 'Pokemon 151',
    rarity: 'Illustration Rare',
    variation: '',
  });
});

test('extension search accepts scraper alias field names', () => {
  const result = buildExtensionSearchTerm({
    pokemonName: 'Mew',
    collectionNumber: '232/091',
    setName: 'Paldean Fates',
    cardVariant: 'ex',
  });

  assert.equal(result.searchTerm, 'Mew ex 232/091 Paldean Fates');
  assert.deepEqual(result.parts, {
    name: 'Mew',
    collectorNumber: '232/091',
    expansion: 'Paldean Fates',
    rarity: '',
    variation: 'ex',
  });
});

test('extension search explicit query overrides structured fields', () => {
  const result = buildExtensionSearchTerm({
    query: 'charizard 199 obsidian',
    name: 'Ignored',
    collectorNumber: '001',
  });

  assert.equal(result.searchTerm, 'charizard 199 obsidian');
  assert.equal(result.source, 'query');
  assert.equal(result.parts.name, 'Ignored');
});

test('extension search blocks illustrator credits from rarity intent', () => {
  const result = buildExtensionSearchTerm({
    name: 'Mesprit',
    collectorNumber: '204/191',
    expansion: 'Surging Sparks',
    rarity: 'Illus. Saya Tsuruta',
  });

  assert.equal(result.searchTerm, 'Mesprit 204/191 Surging Sparks');
  assert.equal(result.parts.rarity, '');
  assert.equal(isIllustratorCredit('Illus. Saya Tsuruta'), true);
  assert.equal(isIllustratorCredit('Illustration Rare'), false);
});

test('extension search preserves real illustration rarity terms', () => {
  const result = buildExtensionSearchTerm({
    name: 'Mew ex',
    collectorNumber: '232/091',
    expansion: 'Paldean Fates',
    rarity: 'Special Illustration Rare',
  });

  assert.equal(result.searchTerm, 'Mew ex 232/091 Paldean Fates Special Illustration Rare');
  assert.equal(result.parts.rarity, 'Special Illustration Rare');
});

test('extension search expands rarityAliases for illustration chip payloads', () => {
  const result = buildExtensionSearchTerm({
    name: 'Sprigatito',
    rarity: 'illustration',
    rarityAliases: [
      'Illustration Rare',
      'Special Illustration Rare',
      'Illus. Artist Name',
      'Illustration Rare',
    ],
  });

  assert.equal(result.searchTerm, 'Sprigatito illustration');
  assert.deepEqual(result.parts.rarityAliases, [
    'Illustration Rare',
    'Special Illustration Rare',
  ]);
  assert.deepEqual(result.searchTerms, [
    'Sprigatito illustration',
    'Sprigatito Illustration Rare',
    'Sprigatito Special Illustration Rare',
  ]);
});

test('extension explicit query strips trailing illustrator credit', () => {
  assert.equal(
    cleanExtensionQuery('Mesprit 204/191 Surging Sparks Illus. Saya Tsuruta'),
    'Mesprit 204/191 Surging Sparks',
  );
});

test('extension search builds canonical public-number marketplace paths', () => {
  assert.equal(
    marketplacePathForRow({
      card_id: '274416',
      name: 'Mew ex',
      set_name: 'Paldean Fates',
      card_number: 'Special Illustration Rare | 232/091',
      rarity: 'Special Illustration Rare',
    }),
    '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
  );
});
