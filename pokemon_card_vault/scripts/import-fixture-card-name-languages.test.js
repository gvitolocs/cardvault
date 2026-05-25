const assert = require('node:assert/strict');
const test = require('node:test');
const {
  canonicalPokemonRoots,
  fixtureEnglishPokemonNames,
  parseCanonicalCardName,
  parseFixture,
  stripKnownVariantText,
} = require('./import-fixture-card-name-languages');

test('parseFixture reads canonical and localized language rows', () => {
  const rows = parseFixture(`
# Pokemon TCG unique printed card names for search testing
## Generation I (#1-#151)
[00001] Bulbasaur
[00010] Mega Venusaur ex

## TCGdex localized name variants
# Format: [EnglishIndex] <language> | <localized name> | tcgdex:<source card id>
### [00010] Mega Venusaur ex
[00010] it | Mega Venusaur-ex | tcgdex:me01-177
[00010] fr | Méga-Florizarre-ex | tcgdex:me01-177
[00010] de | Mega-Bisaflor-ex | tcgdex:me01-177
`);

  assert.deepEqual(
    rows.get('en').map((row) => [row.name, row.localizedName]),
    [
      ['Bulbasaur', 'Bulbasaur'],
      ['Mega Venusaur ex', 'Mega Venusaur ex'],
    ],
  );
  assert.deepEqual(
    rows.get('fr').map((row) => [row.name, row.localizedName, row.sourceCardId]),
    [['Mega Venusaur ex', 'Méga-Florizarre-ex', 'tcgdex:me01-177']],
  );
  assert.deepEqual(
    rows.get('de').map((row) => [row.name, row.localizedName]),
    [['Mega Venusaur ex', 'Mega-Bisaflor-ex']],
  );
});

test('canonicalPokemonRoots strips common variants from fixture names', () => {
  const roots = canonicalPokemonRoots(`
## Generation I (#1-#151)
[00001] Surfing Pikachu
[00002] Pikachu VMAX
[00003] M Venusaur-EX
[00004] Pikachu & Zekrom-GX
## Trainers
[00005] Cynthia
`);

  assert.ok(roots.includes('Pikachu'));
  assert.ok(roots.includes('Venusaur'));
  assert.ok(roots.includes('Pikachu & Zekrom'));
  assert.equal(roots.includes('Cynthia'), false);
});

test('fixtureEnglishPokemonNames stops before trainer section', () => {
  const names = fixtureEnglishPokemonNames(`
## Generation IX (#906-#1025)
[02777] Ceruledge ex
## Trainers
[03111] Brock's Grit
`);

  assert.deepEqual(names, ['Ceruledge ex']);
});

test('stripKnownVariantText keeps pokemon identity for trainer-owned cards', () => {
  assert.equal(stripKnownVariantText("Lt. Surge's Pikachu"), 'Pikachu');
  assert.equal(stripKnownVariantText("Ash's Pikachu GX"), 'Pikachu');
  assert.equal(stripKnownVariantText('Pikachu & Zekrom-GX'), 'Pikachu & Zekrom');
  assert.equal(stripKnownVariantText('M Venusaur-EX'), 'Venusaur');
});

test('parseCanonicalCardName separates pokemon identity, variants, and trainer names', () => {
  const roots = ['Pikachu & Zekrom', 'Venusaur', 'Pikachu'];

  assert.deepEqual(parseCanonicalCardName('Surfing Pikachu', roots), {
    sourceName: 'Surfing Pikachu',
    displayName: 'Surfing Pikachu',
    canonicalName: 'Pikachu',
    productVariant: 'Surfing',
    trainerName: '',
  });
  assert.deepEqual(parseCanonicalCardName("Lt. Surge's Pikachu", roots), {
    sourceName: "Lt. Surge's Pikachu",
    displayName: "Lt. Surge's Pikachu",
    canonicalName: 'Pikachu',
    productVariant: '',
    trainerName: 'Lt. Surge',
  });
  assert.deepEqual(parseCanonicalCardName("Ash's Pikachu GX", roots), {
    sourceName: "Ash's Pikachu GX",
    displayName: "Ash's Pikachu GX",
    canonicalName: 'Pikachu',
    productVariant: 'GX',
    trainerName: 'Ash',
  });
  assert.deepEqual(parseCanonicalCardName('Pikachu & Zekrom-GX', roots), {
    sourceName: 'Pikachu & Zekrom-GX',
    displayName: 'Pikachu & Zekrom-GX',
    canonicalName: 'Pikachu & Zekrom',
    productVariant: 'GX',
    trainerName: '',
  });
  assert.deepEqual(parseCanonicalCardName('M Venusaur-EX', roots), {
    sourceName: 'M Venusaur-EX',
    displayName: 'M Venusaur-EX',
    canonicalName: 'Venusaur',
    productVariant: 'Mega EX',
    trainerName: '',
  });
});

test('parseCanonicalCardName leaves trainer and item cards intact without pokemon roots', () => {
  const roots = ['Pikachu', 'Venusaur'];

  assert.deepEqual(parseCanonicalCardName('Cynthia', roots), {
    sourceName: 'Cynthia',
    displayName: 'Cynthia',
    canonicalName: 'Cynthia',
    productVariant: '',
    trainerName: '',
  });
  assert.deepEqual(parseCanonicalCardName('Rare Candy', roots), {
    sourceName: 'Rare Candy',
    displayName: 'Rare Candy',
    canonicalName: 'Rare Candy',
    productVariant: '',
    trainerName: '',
  });
});
