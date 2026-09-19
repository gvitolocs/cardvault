const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const { parseTcgSearchAliasFile, shouldKeepAlias } = require('./lib/tcg-search-aliases');

const SOURCE = readFileSync(
  join(__dirname, '..', 'data', 'pokemon_tcg_expansion_shortnames_and_card_nicknames.txt'),
  'utf8',
);

test('parser keeps set codes and skips EX mechanic collision', () => {
  const parsed = parseTcgSearchAliasFile(SOURCE);
  const pal = parsed.expansionAliases.filter((row) => row.expansionName === 'Paldea Evolved');
  assert.ok(pal.some((row) => row.alias === 'PAL'));
  assert.ok(pal.some((row) => row.alias === 'PE'));
  const expedition = parsed.expansionAliases.filter((row) => row.expansionName === 'Expedition Base Set');
  assert.ok(expedition.some((row) => row.alias === 'Expedition'));
  assert.equal(expedition.some((row) => /^ex$/i.test(row.alias)), false);
  assert.equal(shouldKeepAlias('EX', 'Expedition Base Set'), false);
  assert.ok(parsed.expansionAliases.some((row) => row.alias === 'SM1S' && row.expansionName === 'Collection Sun'));
  assert.ok(parsed.expansionAliases.some((row) => row.alias === 'CSV10' && /Chasing Glory|Together in Pursuit/i.test(row.expansionName)));
  assert.ok(parsed.expansionAliases.some((row) => row.alias === 'SV10' && row.expansionName === 'Glory of the Rocket Gang'));
});

test('parser extracts moonbreon and split nicknames', () => {
  const parsed = parseTcgSearchAliasFile(SOURCE);
  const moon = parsed.cardNicknames.find((row) => row.nickname === 'Moonbreon');
  assert.equal(moon.cardName, 'Umbreon VMAX');
  assert.equal(moon.expansionName, 'Evolving Skies');
  assert.equal(moon.cardNumber, '215/203');
  assert.ok(parsed.cardNicknames.some((row) => row.nickname === 'Chonkachu'));
  assert.ok(parsed.cardNicknames.some((row) => row.nickname === 'Chunkachu'));
  assert.ok(parsed.cardNicknames.some((row) => row.nickname === 'Van Gogh Pikachu'));
  assert.ok(parsed.expansionAliases.some((row) => row.alias === 'Evolving Cries' && row.expansionName === 'Evolving Skies'));
  const adp = parsed.cardNicknames.find((row) => row.nickname === 'ADP');
  assert.equal(adp.cardNumber, '');
  assert.equal(parsed.cardNicknames.some((row) => /poncho/i.test(row.nickname)), false);
});
