'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { routeForPathname } = require('../server/cardtrader-game-ingest-server');

test('ingest server exposes a specific API per card game', () => {
  assert.equal(routeForPathname('/api/ingest').route.path, '/api/ingest');
  assert.equal(routeForPathname('/api/ingest/magic').params.game, 'magic');
  assert.equal(routeForPathname('/api/ingest/one-piece').params.game, 'one-piece');
  assert.equal(routeForPathname('/api/ingest/one_piece').params.game, 'one_piece');
  assert.equal(routeForPathname('/api/ingest/yugioh').params.game, 'yugioh');
  assert.equal(routeForPathname('/api/ingest/pokemon').params.game, 'pokemon');
});
