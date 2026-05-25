const assert = require('node:assert/strict');
const test = require('node:test');

const {
  bestCandidate,
  buildSetIndex,
  findSetMatch,
  matchWithPokemonTcgData,
  nameScore,
  normalizeArtist,
  normalizeCollectorNumber,
  parseArgs,
  canonicalMissingReason,
  rowFromBlueprint,
  shouldSkipBlueprint,
  upsertArtistsSql,
} = require('./import-marketplace-blueprint-artists');

test('artist importer is dry-run by default and caps concurrency', () => {
  assert.equal(parseArgs([]).apply, false);
  assert.equal(parseArgs(['--apply']).apply, true);
  assert.equal(parseArgs(['--concurrency=250']).concurrency, 100);
  assert.equal(parseArgs(['--limit=all']).limit, Infinity);
});

test('missing report mode is read-only and parses report options', () => {
  const options = parseArgs([
    '--write-missing-report=workflows/reports/artist-import-missing-test.json',
    '--report-sample-size=25',
  ]);
  assert.equal(options.reportMissing, true);
  assert.equal(options.apply, false);
  assert.equal(options.writeMissingReport, 'workflows/reports/artist-import-missing-test.json');
  assert.equal(options.reportSampleSize, 25);
  assert.equal(parseArgs(['--report-eligible-only']).reportEligibleOnly, true);
  assert.throws(
    () => parseArgs(['--apply', '--report-missing']),
    /read-only/,
  );
});

test('artist normalization removes labels without changing search inputs', () => {
  assert.equal(normalizeArtist('Illus. Saya Tsuruta'), 'saya tsuruta');
  assert.equal(normalizeArtist('Illustrator: 5ban Graphics'), '5ban graphics');
  assert.equal(normalizeArtist('Artist: Mitsuhiro Arita'), 'mitsuhiro arita');
});

test('collector normalization matches local and slash numbers', () => {
  assert.equal(normalizeCollectorNumber('Special Illustration Rare | 232/091'), '232');
  assert.equal(normalizeCollectorNumber(' 005 / 131 '), '5');
  assert.equal(normalizeCollectorNumber('SVP 101'), 'SVP101');
});

test('set matching prefers exact normalized set names', () => {
  const index = buildSetIndex([
    { id: 'sv03.5', name: '151' },
    { id: 'swsh3', name: 'Darkness Ablaze' },
  ]);
  const match = findSetMatch({ setName: 'Darkness Ablaze', setCode: '' }, index);
  assert.equal(match.set.id, 'swsh3');
  assert.equal(match.reason, 'set_name_exact');
});

test('candidate matching requires illustrator metadata and confidence', () => {
  const row = {
    name: 'Mew ex',
    setName: 'Paldean Fates',
    collectorNumber: '232/091',
    rarity: 'Special Illustration Rare',
  };
  const result = bestCandidate(row, [
    {
      id: 'sv04.5-232',
      localId: '232',
      name: 'Mew ex',
      rarity: 'Special Illustration Rare',
      illustrator: 'aky CG Works',
    },
  ], 'set_name_exact');
  assert.equal(result.status, 'matched');
  assert.equal(result.best.detail.illustrator, 'aky CG Works');
});

test('pokemon tcg data fallback accepts only known artist names', () => {
  const result = matchWithPokemonTcgData(
    {
      blueprintId: '274416',
      name: 'Mew ex',
      setName: 'Paldean Fates',
      collectorNumber: '232/091',
      rarity: 'Special Illustration Rare',
    },
    {
      bySetNumber: new Map([
        ['paldeanfates:232', [{
          id: 'sv4pt5-232',
          name: 'Mew ex',
          number: '232',
          rarity: 'Special Illustration Rare',
          artist: 'aky CG Works',
          set: { name: 'Paldean Fates' },
        }]],
      ]),
    },
    new Set(['aky cg works']),
  );
  assert.equal(result.status, 'matched');
  assert.equal(result.normalizedArtist, 'aky cg works');
  assert.equal(result.matchReason.includes('local_dataset'), true);
});

test('pokemon tcg data fallback reports unknown artists instead of inserting them', () => {
  const result = matchWithPokemonTcgData(
    {
      blueprintId: '274416',
      name: 'Mew ex',
      setName: 'Paldean Fates',
      collectorNumber: '232/091',
      rarity: 'Special Illustration Rare',
    },
    {
      bySetNumber: new Map([
        ['paldeanfates:232', [{
          id: 'sv4pt5-232',
          name: 'Mew ex',
          number: '232',
          rarity: 'Special Illustration Rare',
          artist: 'New Fallback Artist',
          set: { name: 'Paldean Fates' },
        }]],
      ]),
    },
    new Set(['aky cg works']),
  );
  assert.equal(result.status, 'not_found');
  assert.equal(result.reason, 'unknown_artist_not_in_artist_table');
});

test('row parsing reads metadata without requiring blueprint table artist columns', () => {
  const row = rowFromBlueprint({
    blueprint_id: '274416',
    name: 'Mew ex',
    set_name: 'Paldean Fates',
    card_number: '232/091',
    rarity: 'Special Illustration Rare',
    item_kind: 'single',
    product_type: 'card',
    blueprint: { name: 'Ignored' },
  });
  assert.equal(row.blueprintId, '274416');
  assert.equal(row.name, 'Mew ex');
  assert.equal(shouldSkipBlueprint(row), '');
});

test('upsert SQL targets only the separate artist table', () => {
  const sql = upsertArtistsSql(1);
  assert.match(sql, /public\.marketplace_blueprint_artists/);
  assert.doesNotMatch(sql, /cardtrader_pokemon_blueprints/);
  assert.doesNotMatch(sql, /artist_card_count/);
});

test('name scoring tolerates punctuation variants', () => {
  assert.ok(nameScore("Hop's Zacian ex", 'Hops Zacian ex') > 0.95);
});

test('missing report canonicalizes source reason codes', () => {
  assert.equal(canonicalMissingReason('not_found', 'card_not_found_in_set'), 'card_not_found');
  assert.equal(canonicalMissingReason('ambiguous', 'ambiguous_set_name_contains'), 'ambiguous_set');
  assert.equal(canonicalMissingReason('not_found', 'dataset_not_configured'), 'source_error');
  assert.equal(
    canonicalMissingReason('not_found', 'unknown_artist_not_in_artist_table'),
    'unknown_artist_not_in_artist_table',
  );
  assert.equal(canonicalMissingReason('matched', 'set_name_exact'), 'would_match');
});
