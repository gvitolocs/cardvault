const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const {
  createRawTableSql,
  envNameForGame,
  insertMissingSql,
  insertValues,
  normalizeName,
  objectKeysForRow,
  parseArgs,
  planImageJobs,
  quoteIdent,
  resolveConfiguredTarget,
  rowFromRecord,
  run,
  schemaNameForGame,
} = require('./cardtrader-multigame-import');

test('parseArgs defaults to dry-run and accepts isolated target flags', () => {
  const options = parseArgs([
    '--game=magic',
    '--cardtrader-game-id=1',
    '--database-url-env=MAGIC_MARKETPLACE_DATABASE_URL',
    '--schema=marketplace_magic',
    '--table=cardtrader_blueprints',
    '--expansion-ids=10,11',
    '--images',
    '--concurrency=12',
    '--image-concurrency=8',
  ]);

  assert.equal(options.apply, false);
  assert.equal(options.game, 'magic');
  assert.equal(options.cardtraderGameId, 1);
  assert.equal(options.databaseUrlEnv, 'MAGIC_MARKETPLACE_DATABASE_URL');
  assert.equal(options.schema, 'marketplace_magic');
  assert.equal(options.table, 'cardtrader_blueprints');
  assert.deepEqual(options.expansionIds, [10, 11]);
  assert.equal(options.images, true);
  assert.equal(options.concurrency, 12);
  assert.equal(options.imageConcurrency, 8);
});

test('parseArgs rejects unbounded non-discovery import', () => {
  assert.throws(() => parseArgs(['--game=magic']), /bounded multi-game import/);
});

test('target defaults keep Pokemon legacy path and isolate other games', () => {
  const pokemon = resolveConfiguredTarget(parseArgs(['--game=Pokemon', '--discover-only']), {});
  const magic = resolveConfiguredTarget(parseArgs(['--game=Magic: the Gathering', '--discover-only']), {});

  assert.equal(pokemon.databaseUrlEnv, 'MARKETPLACE_DATABASE_URL');
  assert.equal(pokemon.schema, 'public');
  assert.equal(pokemon.table, 'cardtrader_pokemon_blueprints');
  assert.equal(magic.databaseUrlEnv, 'MAGIC_THE_GATHERING_MARKETPLACE_DATABASE_URL');
  assert.equal(magic.schema, 'marketplace_magic_the_gathering');
  assert.equal(magic.table, 'cardtrader_blueprints');
  assert.equal(magic.cdnKeyPrefix, 'magic-the-gathering/');
});

test('configured target can declare per-game placeholders without secrets', () => {
  const target = resolveConfiguredTarget(
    parseArgs(['--game=magic', '--discover-only']),
    {
      games: {
        magic: {
          displayName: 'Magic: the Gathering',
          cardtraderGameId: 1,
          databaseUrlEnv: 'MAGIC_MARKETPLACE_DATABASE_URL',
          schema: 'marketplace_magic',
          table: 'cardtrader_blueprints',
          cdnKeyPrefix: 'magic/',
        },
      },
    },
  );

  assert.equal(target.displayName, 'Magic: the Gathering');
  assert.equal(target.cardtraderGameId, 1);
  assert.equal(target.databaseUrlEnv, 'MAGIC_MARKETPLACE_DATABASE_URL');
  assert.equal(target.schema, 'marketplace_magic');
  assert.equal(target.cdnKeyPrefix, 'magic/');
});

test('schema SQL creates only requested namespace table', () => {
  const target = {
    schema: 'marketplace_magic',
    table: 'cardtrader_blueprints',
  };
  const sql = createRawTableSql(target);

  assert.match(sql, /create schema if not exists "marketplace_magic"/);
  assert.match(sql, /create table if not exists "marketplace_magic"\."cardtrader_blueprints"/);
  assert.doesNotMatch(sql, /cardtrader_pokemon_blueprints/);
  assert.doesNotMatch(sql, /marketplace_search_candidates/);
});

test('identifier quoting rejects unsafe schema and table names', () => {
  assert.equal(quoteIdent('marketplace_magic'), '"marketplace_magic"');
  assert.throws(() => quoteIdent('public;drop schema public'), /Unsafe SQL identifier/);
});

test('insert SQL is idempotent and isolated', () => {
  const target = {
    schema: 'marketplace_magic',
    table: 'cardtrader_blueprints',
  };
  const sql = insertMissingSql(2, target);

  assert.match(sql, /insert into "marketplace_magic"\."cardtrader_blueprints"/);
  assert.match(sql, /on conflict \(id\) do nothing/);
  assert.match(sql, /returning id/);
  assert.doesNotMatch(sql.toLowerCase(), /truncate|delete from/);
  assert.doesNotMatch(sql, /cardtrader_pokemon_blueprints|marketplace_cards/);
});

test('row mapping and insert values preserve generic CardTrader fields', () => {
  const row = rowFromRecord({
    blueprint: {
      id: 123,
      name: 'Lightning Bolt',
      game_id: 1,
      category_id: 44,
      expansion_id: 55,
      tcg_player_id: 999,
      editable_properties: [{ name: 'condition' }],
    },
    expansion: { id: 55, name: 'Example Set' },
  });
  const values = insertValues([row]);

  assert.equal(row.name, 'Lightning Bolt');
  assert.deepEqual(row.tcg_player_ids, [999]);
  assert.equal(values[0], 123);
  assert.equal(values[1], 'Lightning Bolt');
  assert.equal(values[8], '[999]');
  assert.match(values[10], /Lightning Bolt/);
});

test('dry-run without target database reports blocker and schema plan', async () => {
  const previous = process.env.MAGIC_MARKETPLACE_DATABASE_URL;
  delete process.env.MAGIC_MARKETPLACE_DATABASE_URL;
  try {
    const result = await run(
      parseArgs([
        '--game=magic',
        '--cardtrader-game-id=1',
        '--database-url-env=MAGIC_MARKETPLACE_DATABASE_URL',
        '--schema=marketplace_magic',
        '--table=cardtrader_blueprints',
        '--expansion-ids=10',
        '--images',
      ]),
      {
        api: {
          get: async (apiPath) => {
            if (apiPath === '/games') return [{ id: 1, name: 'Magic', display_name: 'Magic: the Gathering' }];
            if (apiPath === '/categories') return [{ id: 44, game_id: 1, name: 'Cards' }];
            if (apiPath === '/expansions') return [{ id: 10, game_id: 1, name: 'Alpha' }];
            throw new Error(`unexpected ${apiPath}`);
          },
        },
        config: {},
      },
    );

    assert.equal(result.mode, 'dry-run');
    assert.match(result.blockers[0], /MAGIC_MARKETPLACE_DATABASE_URL is not configured/);
    assert.match(result.schemaPlan, /"marketplace_magic"\."cardtrader_blueprints"/);
    assert.equal(result.imageResult.skipped, 'no newly imported ids');
  } finally {
    if (previous) process.env.MAGIC_MARKETPLACE_DATABASE_URL = previous;
  }
});

test('dry-run comparison plans only missing rows and new image jobs', async () => {
  const queries = [];
  const pool = {
    async query(sql, values) {
      queries.push({ sql, values });
      if (/select id::text as id/.test(sql)) {
        return { rows: [{ id: '1' }] };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  };
  const result = await run(
    parseArgs([
      '--game=magic',
      '--cardtrader-game-id=1',
      '--database-url-env=MAGIC_MARKETPLACE_DATABASE_URL',
      '--schema=marketplace_magic',
      '--table=cardtrader_blueprints',
      '--expansion-ids=10',
      '--images',
      '--limit=all',
    ]),
    {
      pool,
      api: {
        get: async (apiPath, params) => {
          if (apiPath === '/games') return [{ id: 1, name: 'Magic', display_name: 'Magic: the Gathering' }];
          if (apiPath === '/categories') return [{ id: 44, game_id: 1, name: 'Cards' }];
          if (apiPath === '/expansions') return [{ id: 10, game_id: 1, name: 'Alpha' }];
          if (apiPath === '/blueprints/export' && params.expansion_id === 10) {
            return [
              { id: 1, name: 'Existing', game_id: 1, category_id: 44, expansion_id: 10 },
              { id: 2, name: 'Missing', game_id: 1, category_id: 44, expansion_id: 10 },
            ];
          }
          throw new Error(`unexpected ${apiPath}`);
        },
      },
      config: {},
    },
  );

  assert.equal(result.counts.fetched, 2);
  assert.equal(result.counts.existingRaw, 1);
  assert.equal(result.counts.missingRaw, 1);
  assert.equal(result.counts.inserted, 0);
  assert.deepEqual(result.missingSamples.map((row) => row.id), [2]);
  assert.deepEqual(result.imageResult.chunks, [{ ids: [2] }]);
  assert.equal(queries.length, 1);
});

test('apply comparison inserts missing rows and images only inserted ids', async () => {
  const queries = [];
  const pool = {
    async query(sql, values) {
      queries.push({ sql, values });
      if (/select id::text as id/.test(sql)) {
        return { rows: [{ id: '1' }] };
      }
      if (/insert into "marketplace_magic"\."cardtrader_blueprints"/.test(sql)) {
        return { rowCount: 1, rows: [{ id: '2' }] };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  };
  const result = await run(
    parseArgs([
      '--game=magic',
      '--cardtrader-game-id=1',
      '--database-url-env=MAGIC_MARKETPLACE_DATABASE_URL',
      '--schema=marketplace_magic',
      '--table=cardtrader_blueprints',
      '--expansion-ids=10',
      '--images',
      '--apply',
    ]),
    {
      pool,
      api: {
        get: async (apiPath, params) => {
          if (apiPath === '/games') return [{ id: 1, name: 'Magic', display_name: 'Magic: the Gathering' }];
          if (apiPath === '/categories') return [{ id: 44, game_id: 1, name: 'Cards' }];
          if (apiPath === '/expansions') return [{ id: 10, game_id: 1, name: 'Alpha' }];
          if (apiPath === '/blueprints/export' && params.expansion_id === 10) {
            return [
              { id: 1, name: 'Existing', game_id: 1, category_id: 44, expansion_id: 10 },
              { id: 2, name: 'Missing', game_id: 1, category_id: 44, expansion_id: 10 },
            ];
          }
          throw new Error(`unexpected ${apiPath}`);
        },
      },
      config: {},
    },
  );

  assert.equal(result.counts.inserted, 1);
  assert.deepEqual(result.imageResult.chunks, [{ ids: [2] }]);
  assert.equal(queries.length, 2);
});

test('image key planning applies game CDN prefix and three derivatives', () => {
  const target = { cdnKeyPrefix: 'magic/' };
  const keys = objectKeysForRow({ id: 123, name: 'Lightning Bolt' }, target, 'jpg');
  const plan = planImageJobs([123, 456], {
    schema: 'marketplace_magic',
    table: 'cardtrader_blueprints',
    cdnKeyPrefix: 'magic/',
  }, {
    images: true,
    imageChunkSize: 1,
  });

  assert.equal(keys.fullKey, 'magic/123_lightning-bolt.jpg');
  assert.equal(keys.previewKey, 'magic/previews/123_lightning-bolt.webp');
  assert.equal(keys.homepageKey, 'magic/123_lightning-bolt_homepage.webp');
  assert.deepEqual(plan.derivatives, ['full', 'preview', 'homepage']);
  assert.deepEqual(plan.chunks, [{ ids: [123] }, { ids: [456] }]);
});

test('helper names normalize game envs and schemas', () => {
  assert.equal(normalizeName('Pokémon: Élite'), 'pokemon elite');
  assert.equal(envNameForGame('One Piece'), 'ONE_PIECE_MARKETPLACE_DATABASE_URL');
  assert.equal(schemaNameForGame('Disney Lorcana'), 'marketplace_disney_lorcana');
});

test('script passes node syntax check', () => {
  const script = path.join(__dirname, 'cardtrader-multigame-import.js');
  assert.equal(spawnSync(process.execPath, ['--check', script]).status, 0);
});
