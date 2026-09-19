'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { indexPokemontcgSets, matchPokemontcgSet } = require('./pokemontcg-sets');
const { parseQwenJson, shouldAskQwen } = require('./qwen-card-compare');

const SETS = [
  { id: 'base1', name: 'Base' },
  { id: 'sv3pt5', name: '151' },
  { id: 'sv1', name: 'Scarlet & Violet' },
  { id: 'me1', name: 'Mega Evolution' },
  { id: 'me2', name: 'Phantasmal Flames' },
  { id: 'neo3', name: 'Neo Revelation' },
];

test('marketplace expansion names map onto pokemontcg set ids', () => {
  const index = indexPokemontcgSets(SETS);
  assert.equal(matchPokemontcgSet('Base Set', index).setId, 'base1');
  assert.equal(matchPokemontcgSet('151', index).setId, 'sv3pt5');
  assert.equal(matchPokemontcgSet('Scarlet & Violet', index).setId, 'sv1');
  assert.equal(matchPokemontcgSet('Mega Evolution', index).setId, 'me1');
  assert.equal(matchPokemontcgSet('Phantasmal Flames', index).setId, 'me2');
  assert.equal(matchPokemontcgSet('Neo Revelation', index).setId, 'neo3');
  assert.equal(matchPokemontcgSet('10th Movie Commemoration Set', index).setId, null);
});

test('Qwen JSON is parsed from fenced model output', () => {
  const parsed = parseQwenJson('```json\n{"same_card":true,"winner":"api","reason":"hires scan"}\n```');
  assert.deepEqual(parsed, { same_card: true, winner: 'api', reason: 'hires scan' });
  assert.equal(parseQwenJson('nope'), null);
});

test('Qwen is skipped on obvious pixel wins and losses', () => {
  assert.equal(shouldAskQwen({ better: true, ratio: 3.4, mapped: true }), false);
  assert.equal(shouldAskQwen({ better: false, ratio: 0.97, mapped: true }), true);
  assert.equal(shouldAskQwen({ better: false, ratio: 0.5, mapped: true }), false);
  assert.equal(shouldAskQwen({ better: true, ratio: 1.44, mapped: true }), true);
  assert.equal(shouldAskQwen({ mapped: false, ratio: 3, better: true }), false);
  assert.equal(shouldAskQwen({ better: false, ratio: 1, mapped: true }), false);
});
