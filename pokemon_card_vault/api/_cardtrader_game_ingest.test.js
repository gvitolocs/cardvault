'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  INGEST_GAMES,
  ingestGameList,
  isPokemonIngestGame,
  normalizeIngestGame,
  ingestGameConfig,
  ingestApiPath,
  ingestListenPort,
  ingestDatabaseUrl,
  pokemonStaysOnPiError,
  authorizeIngestRequest,
  importerOptionsForGame,
  assertBoundedApply,
} = require('./_cardtrader_game_ingest');

test('ingest catalog skips pokemon and covers CardTrader games', () => {
  const ids = ingestGameList().map((game) => game.id);
  assert.equal(ids.includes('pokemon'), false);
  assert.equal(Boolean(INGEST_GAMES.magic), true);
  assert.equal(INGEST_GAMES.magic.cardtraderGameId, 1);
  assert.equal(INGEST_GAMES.yugioh.cardtraderGameId, 4);
  assert.equal(INGEST_GAMES.one_piece.database, 'pokoin_one_piece');
  assert.equal(INGEST_GAMES.riftbound.cdnKeyPrefix, 'riftbound/');
});

test('pokemon aliases are refused as ingest games', () => {
  assert.equal(isPokemonIngestGame('pokemon'), true);
  assert.equal(isPokemonIngestGame('poke'), true);
  assert.equal(normalizeIngestGame('pokemon'), 'pokemon');
  assert.equal(ingestGameConfig('pokemon'), null);
  assert.equal(pokemonStaysOnPiError().statusCode, 404);
});

test('normalizeIngestGame maps slugs and aliases', () => {
  assert.equal(normalizeIngestGame('one-piece'), 'one_piece');
  assert.equal(normalizeIngestGame('mtg'), 'magic');
  assert.equal(normalizeIngestGame('yu-gi-oh'), 'yugioh');
  assert.equal(normalizeIngestGame('lorcana'), 'lorcana');
  assert.equal(ingestApiPath('magic'), '/api/ingest/magic');
  assert.equal(ingestListenPort(INGEST_GAMES.magic), 18101);
  assert.equal(ingestListenPort(INGEST_GAMES.one_piece), 18115);
});

test('ingestDatabaseUrl derives 15T path from MARKETPLACE_DATABASE_URL', () => {
  const env = {
    MARKETPLACE_DATABASE_URL: 'postgres://pokoin_marketplace:x@127.0.0.1:15543/pokoin_marketplace',
    MARKETPLACE_DATABASE_SSL: '0',
  };
  assert.equal(
    ingestDatabaseUrl('magic', env),
    'postgres://pokoin_marketplace:x@127.0.0.1:15543/pokoin_magic',
  );
  assert.equal(
    ingestDatabaseUrl('one_piece', env),
    'postgres://pokoin_marketplace:x@127.0.0.1:15543/pokoin_one_piece',
  );
  const required = {
    MAGIC_MARKETPLACE_DATABASE_URL:
      'postgres://pokoin_marketplace:x@127.0.0.1:15543/pokoin_magic?uselibpqcompat=true&sslmode=require',
    MARKETPLACE_DATABASE_SSL: '0',
  };
  assert.equal(
    ingestDatabaseUrl('magic', required),
    'postgres://pokoin_marketplace:x@127.0.0.1:15543/pokoin_magic?uselibpqcompat=true',
  );
});

test('authorizeIngestRequest accepts bearer secret', () => {
  const env = { CARDTRADER_INGEST_SECRET: 'ingest-secret' };
  assert.equal(
    authorizeIngestRequest({ headers: { authorization: 'Bearer ingest-secret' } }, env).type,
    'ingest_secret',
  );
  assert.throws(
    () => authorizeIngestRequest({ headers: { authorization: 'Bearer no' } }, env),
    (error) => error.statusCode === 401,
  );
});

test('apply ingest refuses unbounded stream-all', () => {
  const config = INGEST_GAMES.magic;
  const options = importerOptionsForGame(config, { apply: true, streamAll: true });
  assert.throws(
    () => assertBoundedApply(options, { apply: true, streamAll: true }),
    (error) => error.code === 'INGEST_STREAM_ALL_CONFIRM',
  );
  assert.doesNotThrow(() => assertBoundedApply(options, { confirm: 'stream-all' }));
  assert.throws(
    () => assertBoundedApply(importerOptionsForGame(config, { apply: true }), { apply: true }),
    (error) => error.code === 'INGEST_APPLY_BOUNDED',
  );
});
