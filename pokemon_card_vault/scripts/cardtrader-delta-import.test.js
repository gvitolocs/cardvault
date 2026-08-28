const test = require('node:test');
const assert = require('node:assert/strict');

const {
  insertMissingSql,
  insertValues,
  normalizeName,
  parseArgs,
  rowFromRecord,
  tcgPlayerIds,
  uniqueRecords,
} = require('./cardtrader-delta-import');

test('parseArgs defaults to dry-run bounded delta', () => {
  const options = parseArgs(['--expansion-ids=4611,4639']);

  assert.equal(options.apply, false);
  assert.deepEqual(options.expansionIds, [4611, 4639]);
  assert.equal(options.images, false);
  assert.equal(options.refresh, false);
  assert.equal(options.syncSupabase, false);
});

test('parseArgs supports full streaming API mode', () => {
  const options = parseArgs(['--stream-all', '--images', '--refresh', '--sync-supabase']);

  assert.equal(options.streamAll, true);
  assert.equal(options.images, true);
  assert.equal(options.refresh, true);
  assert.equal(options.syncSupabase, true);
});

test('parseArgs rejects unbounded API import', () => {
  assert.throws(() => parseArgs([]), /bounded delta import/);
});

test('normalizeName supports accented Pokemon expansion names', () => {
  assert.equal(normalizeName('Pokémon: Pitch-Black'), 'pokemon pitch black');
});

test('rowFromRecord maps CardTrader single tcg_player_id to json array', () => {
  const row = rowFromRecord({
    blueprint: {
      id: 1,
      name: 'Mega Darkrai ex',
      game_id: 5,
      category_id: 73,
      expansion_id: 4611,
      tcg_player_id: 12345,
      editable_properties: [],
    },
    expansion: { id: 4611, name: 'Abyss Eye' },
  });

  assert.equal(row.id, 1);
  assert.equal(row.name, 'Mega Darkrai ex');
  assert.deepEqual(row.tcg_player_ids, [12345]);
  assert.equal(row.expansion.name, 'Abyss Eye');
});

test('rowFromRecord does not persist CardTrader fallback preview as image_url', () => {
  const row = rowFromRecord({
    blueprint: {
      id: 390877,
      name: 'Chien-Pao',
      game_id: 5,
      category_id: 73,
      expansion_id: 4639,
      image_url: 'https://cardtrader.com/fallbacks/card_uploader/preview.png',
      editable_properties: [],
    },
    expansion: { id: 4639, name: 'Stellar Crystal' },
  });

  assert.equal(row.image_url, null);
  assert.match(row.blueprint.image_url, /fallbacks\/card_uploader\/preview\.png/);
});

test('tcgPlayerIds preserves array and omits empty scalar', () => {
  assert.deepEqual(tcgPlayerIds({ tcg_player_ids: [1, 2] }), [1, 2]);
  assert.equal(tcgPlayerIds({ tcg_player_id: '' }), null);
});

test('uniqueRecords dedupes by CardTrader blueprint id', () => {
  const rows = uniqueRecords([
    { blueprint: { id: 1, name: 'First', game_id: 5 }, expansion: {} },
    { blueprint: { id: 1, name: 'Duplicate', game_id: 5 }, expansion: {} },
    { blueprint: { id: 2, name: 'Second', game_id: 5 }, expansion: {} },
  ]);

  assert.deepEqual(rows.map((row) => row.id), [1, 2]);
});

test('insert SQL only inserts missing raw blueprint rows', () => {
  const sql = insertMissingSql(2);

  assert.match(sql, /insert into public\.cardtrader_pokemon_blueprints/);
  assert.match(sql, /on conflict \(id\) do nothing/);
  assert.doesNotMatch(sql.toLowerCase(), /truncate|delete from/);
  assert.doesNotMatch(sql, /marketplace_cards|marketplace_search_candidates/);
});

test('insertValues serializes json columns', () => {
  const values = insertValues([
    rowFromRecord({
      blueprint: {
        id: 1,
        name: 'Mega Darkrai ex',
        game_id: 5,
        category_id: 73,
        expansion_id: 4611,
        card_market_ids: [111],
        tcg_player_id: 222,
        editable_properties: [{ name: 'condition' }],
      },
      expansion: { id: 4611, name: 'Abyss Eye' },
    }),
  ]);

  assert.equal(values[0], 1);
  assert.equal(values[1], 'Mega Darkrai ex');
  assert.equal(values[7], '[111]');
  assert.equal(values[8], '[222]');
  assert.match(values[9], /condition/);
  assert.match(values[10], /Mega Darkrai ex/);
  assert.match(values[11], /Abyss Eye/);
});

test('dry-run image plan chunks large id sets', () => {
  const { spawnSync } = require('node:child_process');
  const source = require('node:fs').readFileSync(
    require('node:path').join(__dirname, 'cardtrader-delta-import.js'),
    'utf8',
  );

  assert.match(source, /function chunkArray/);
  assert.match(source, /CARDTRADER_DELTA_IMAGE_CHUNK_SIZE/);
  assert.match(source, /set statement_timeout = 0/);
  assert.match(source, /refresh_marketplace_cards_from_blueprints/);
  assert.match(source, /refresh_marketplace_blueprint_price_summary/);
  assert.match(source, /CardTrader \/blueprints\/export returns full blueprint rows per expansion/);
  assert.equal(spawnSync(process.execPath, ['--check', require('node:path').join(__dirname, 'cardtrader-delta-import.js')]).status, 0);
});
