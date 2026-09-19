'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  cardmarketSearchFallbackUrl,
  cardmarketGamePath,
} = require('./cardmarket-redirect');

test('Cardmarket game paths', () => {
  assert.equal(cardmarketGamePath('pokemon'), 'Pokemon');
  assert.equal(cardmarketGamePath('one_piece'), 'OnePiece');
  assert.equal(cardmarketGamePath('riftbound'), 'Riftbound');
});

test('One Piece Cardmarket fallback is a Search URL, not Pokemon Singles', () => {
  const url = cardmarketSearchFallbackUrl({ name: 'Sanji' }, 'en', 'one_piece');
  assert.match(url, /cardmarket\.com\/en\/OnePiece\/Products\/Search/);
  assert.match(url, /searchString=Sanji/);
  assert.doesNotMatch(url, /Pokemon/);
});

test('Pokemon Cardmarket fallback is name plus collector, not set name', () => {
  const url = cardmarketSearchFallbackUrl({
    name: 'Dawn',
    expansion_name: 'Majestic Dawn',
    expansion_number: '129/100',
  }, 'en', 'pokemon');
  assert.match(url, /Pokemon\/Products\/Singles/);
  assert.match(url, /searchString=dawn\+129/);
  assert.doesNotMatch(url, /Majestic/);
});

test('Pokemon Cardmarket fallback uses the hash from a rarity pipe number', () => {
  const url = cardmarketSearchFallbackUrl({
    name: 'Gumshoos',
    expansion_number: 'Illustration Rare | 184/182',
  }, 'en', 'pokemon');
  assert.match(url, /searchString=gumshoos\+184/);
});

test('One Piece Cardmarket fallback adds the collector when present', () => {
  const url = cardmarketSearchFallbackUrl({
    name: 'Sanji',
    expansion_number: 'OP01-013',
  }, 'en', 'one_piece');
  assert.match(url, /searchString=Sanji\+OP01-013/);
});
