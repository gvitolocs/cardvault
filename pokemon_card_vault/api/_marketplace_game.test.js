'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeGame,
  gameIdFromHost,
  parseGameFromRequest,
  parseGameFromHost,
} = require('./_marketplace_game');

test('normalizeGame accepts satellite aliases', () => {
  assert.equal(normalizeGame('one-piece'), 'one_piece');
  assert.equal(normalizeGame('onepiece'), 'one_piece');
  assert.equal(normalizeGame('op'), 'one_piece');
  assert.equal(normalizeGame('riftbound'), 'riftbound');
  assert.equal(normalizeGame('rb'), 'riftbound');
  assert.equal(normalizeGame('magic'), 'magic');
  assert.equal(normalizeGame('mtg'), 'magic');
  assert.equal(normalizeGame('yugioh'), 'yugioh');
  assert.equal(normalizeGame(''), 'pokemon');
});

test('gameIdFromHost maps satellite hostnames', () => {
  assert.equal(gameIdFromHost('onepiece.pokoin.com'), 'one_piece');
  assert.equal(gameIdFromHost('riftbound.pokoin.com'), 'riftbound');
  assert.equal(gameIdFromHost('magic.pokoin.com'), 'magic');
  assert.equal(gameIdFromHost('yugioh.pokoin.com'), 'yugioh');
  assert.equal(gameIdFromHost('pokoin.com'), 'pokemon');
  assert.equal(gameIdFromHost('api.pokoin.com'), 'pokemon');
});

test('parseGameFromRequest prefers query over host', () => {
  assert.equal(
    parseGameFromRequest({
      url: '/api/marketplace-home-page?game=riftbound',
      headers: { host: 'onepiece.pokoin.com' },
    }),
    'riftbound',
  );
});

test('parseGameFromRequest uses satellite Host when query missing', () => {
  assert.equal(
    parseGameFromRequest({
      url: '/api/marketplace-home-page',
      headers: { host: 'onepiece.pokoin.com' },
    }),
    'one_piece',
  );
  assert.equal(
    parseGameFromRequest({
      url: '/api/marketplace-home-page',
      headers: { host: 'riftbound.pokoin.com' },
    }),
    'riftbound',
  );
});

test('parseGameFromRequest uses x-forwarded-host behind api.pokoin.com proxy', () => {
  assert.equal(
    parseGameFromRequest({
      url: '/api/marketplace-home-page',
      headers: {
        host: 'api.pokoin.com',
        'x-forwarded-host': 'onepiece.pokoin.com',
      },
    }),
    'one_piece',
  );
  assert.equal(
    parseGameFromHost({
      headers: {
        host: 'api.pokoin.com',
        origin: 'https://riftbound.pokoin.com',
      },
    }),
    'riftbound',
  );
});

test('parseGameFromRequest keeps pokemon on api host without satellite hints', () => {
  assert.equal(
    parseGameFromRequest({
      url: '/api/marketplace-home-page',
      headers: { host: 'api.pokoin.com' },
    }),
    'pokemon',
  );
});
