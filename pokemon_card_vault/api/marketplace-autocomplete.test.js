const assert = require('node:assert/strict');
const test = require('node:test');
const {
  cleanAutocompletePoolLimit,
  poolSearchTerm,
  rankAutocompleteRows,
} = require('./marketplace-autocomplete');

function row({
  id,
  name,
  set = 'Test Set',
  number = '001/100',
  rarity = 'Card',
  type = 'Lightning',
  kind = 'single',
  trainer = '',
  rank = 0,
}) {
  return {
    card_id: id,
    name,
    set_name: set,
    card_number: number,
    rarity,
    card_type: type,
    item_kind: kind,
    trainer_name: trainer,
    search_rank: rank,
  };
}

test('autocomplete fetches the full query for tokenized database search', () => {
  assert.equal(poolSearchTerm('porygon'), 'porygon');
  assert.equal(poolSearchTerm('piachu 151'), 'piachu 151');
  assert.equal(poolSearchTerm('  char ex  '), 'char ex');
});

test('autocomplete pool limit is at least one thousand', () => {
  assert.equal(cleanAutocompletePoolLimit(undefined), 1000);
  assert.equal(cleanAutocompletePoolLimit(20), 1000);
  assert.equal(cleanAutocompletePoolLimit(1000), 1000);
  assert.equal(cleanAutocompletePoolLimit(2500), 2500);
});

test('autocomplete can return a large ranked background pool', () => {
  const cards = Array.from({ length: 40 }, (_, index) =>
    row({
      id: `${index}`,
      name: `Miraidon ${index}`,
      number: `${index + 1}/100`,
    }),
  );

  assert.equal(rankAutocompleteRows(cards, 'mir', 35).length, 35);
});

test('exact static catalog query keeps Porygon variants and rejects prefix noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Porygon', set: '151', number: '137/165' }),
      row({ id: '2', name: 'Porygon2', set: 'Stellar Crown' }),
      row({ id: '3', name: 'Porygon-Z', set: 'Unbroken Bonds' }),
      row({ id: '4', name: 'Vaporeon', set: 'Display Set Gift Box' }),
      row({ id: '5', name: 'Pokemon Communication' }),
    ],
    'porygon',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.name),
    ['Porygon', 'Porygon-Z', 'Porygon2'],
  );
});

test('common misspells still resolve to the intended blueprint names', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu ex' }),
      row({ id: '2', name: 'Pidgeot ex' }),
      row({ id: '3', name: 'Gardevoir ex' }),
      row({ id: '4', name: 'Energy Switch', set: 'Gardevoir Deck' }),
    ],
    'gardevior',
    20,
  );

  assert.equal(results[0].name, 'Gardevoir ex');
});

test('collector abbreviations rank shorthand names before unrelated matches', () => {
  const cards = [
    row({ id: '1', name: 'Charizard ex', set: '151' }),
    row({ id: '2', name: 'Charmander', set: '151' }),
    row({ id: '3', name: 'Venusaur ex', set: '151' }),
    row({ id: '4', name: 'Blastoise ex', set: '151' }),
  ];

  assert.equal(rankAutocompleteRows(cards, 'char ex', 20)[0].name, 'Charizard ex');
  assert.equal(rankAutocompleteRows(cards, 'venu ex', 20)[0].name, 'Venusaur ex');
  assert.equal(rankAutocompleteRows(cards, 'blast ex', 20)[0].name, 'Blastoise ex');
});

test('products are shown after matching single-card blueprints', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Eevee', kind: 'single' }),
      row({ id: '2', name: 'Eevee Display Set Gift Box', kind: 'product' }),
    ],
    'eevee',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.item_kind),
    ['single', 'product'],
  );
});

test('multi-token number searches rank matching name and set-number rows first', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: '151', number: '025/165' }),
      row({ id: '2', name: 'Pikachu ex', set: 'Journey Together', number: '179/159' }),
      row({ id: '3', name: 'Charmander', set: '151', number: '004/165' }),
    ],
    'pikachu 151',
    20,
  );

  assert.equal(results[0].name, 'Pikachu');
  assert.equal(results[0].set_name, '151');
});

test('multi-token rarity searches keep the named card above rarity-only rows', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mew ex',
        set: 'Paldean Fates',
        number: '232/091',
        rarity: 'Special Illustration Rare',
      }),
      row({
        id: '2',
        name: 'Mewtwo ex',
        set: 'Paradox Rift',
        number: '058/182',
        rarity: 'Double Rare',
      }),
      row({
        id: '3',
        name: 'Energy Switch',
        set: 'Deck',
        rarity: 'Special Illustration Rare',
      }),
    ],
    'mew special illustration rare',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('remote tokenized rank keeps typo plus expansion candidates visible', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: '151', number: '025/165', rank: 9000 }),
      row({ id: '2', name: 'Charmander', set: '151', number: '004/165', rank: 2400 }),
    ],
    'piachu 151',
    20,
  );

  assert.equal(results[0].name, 'Pikachu');
  assert.equal(results[0].set_name, '151');
});

test('short name typo plus collector number beats expansion-code noise', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mew ex',
        set: 'Paldean Fates',
        number: 'Special Illustration Rare | 232/091',
      }),
      row({
        id: '2',
        name: 'Basic Darkness Energy',
        set: 'Mega Evolution Energies',
        number: 'MEE 007',
        type: 'Energy',
        rank: 2640,
      }),
      row({
        id: '3',
        name: 'Basic Fire Energy',
        set: 'Mega Evolution Energies',
        number: 'MEE 002',
        type: 'Energy',
        rank: 2640,
      }),
    ],
    'mee 232',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('short name typo plus variation keeps intended pokemon visible', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Mew ex', set: 'Paldean Fates', number: '232/091' }),
      row({ id: '2', name: 'Meowth', set: 'EX Team Rocket Returns' }),
    ],
    'mee ex',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('name and suffix token matches beat set-only product noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Charizard ex', set: '151' }),
      row({ id: '2', name: 'Charcadet', set: 'ex Premium Collection' }),
      row({ id: '3', name: 'Charizard', set: 'EX Dragon' }),
    ],
    'char ex',
    20,
  );

  assert.equal(results[0].name, 'Charizard ex');
});

test('pokemon name prefixes beat expansion and set-name pool noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Miraidon', set: 'Scarlet & Violet Promos' }),
      row({ id: '2', name: 'Miracle Berry', set: 'Neo Genesis', type: 'Item' }),
      row({ id: '3', name: 'Jirachi EX', set: 'Miracle Crystal' }),
      row({ id: '4', name: 'Girafarig', set: 'Mirage Forest' }),
    ],
    'mir',
    20,
  );

  assert.equal(results[0].name, 'Miraidon');
});
