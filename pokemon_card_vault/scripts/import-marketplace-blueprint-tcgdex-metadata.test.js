const assert = require('node:assert/strict');
const test = require('node:test');

const {
  bestCandidate,
  buildSetIndex,
  canonicalReason,
  findSetMatch,
  metadataFromDetail,
  normalizeCollectorNumber,
  parseArgs,
  rowFromBlueprint,
  shouldSkipBlueprint,
  upsertMetadataSql,
} = require('./import-marketplace-blueprint-tcgdex-metadata');

test('tcgdex metadata importer is dry-run by default and rate-caps remote concurrency', () => {
  assert.equal(parseArgs([]).apply, false);
  assert.equal(parseArgs(['--apply']).apply, true);
  assert.equal(parseArgs(['--limit=all']).limit, Infinity);
  assert.equal(parseArgs(['--concurrency=250']).concurrency, 100);
  assert.equal(parseArgs(['--tcgdex-min-interval-ms=0']).tcgdexMinIntervalMs, 0);
});

test('missing report mode is read-only', () => {
  const options = parseArgs([
    '--write-missing-report=workflows/reports/tcgdex-metadata-missing-test.json',
    '--report-sample-size=25',
  ]);
  assert.equal(options.reportMissing, true);
  assert.equal(options.apply, false);
  assert.equal(options.writeMissingReport, 'workflows/reports/tcgdex-metadata-missing-test.json');
  assert.equal(options.reportSampleSize, 25);
  assert.throws(
    () => parseArgs(['--apply', '--report-missing']),
    /read-only/,
  );
});

test('collector normalization matches local and slash numbers', () => {
  assert.equal(normalizeCollectorNumber('Special Illustration Rare | 232/091'), '232');
  assert.equal(normalizeCollectorNumber(' 005 / 131 '), '5');
  assert.equal(normalizeCollectorNumber('SVP 101'), 'SVP101');
});

test('set matching accepts TCGdex abbreviations and exact names', () => {
  const index = buildSetIndex([
    { id: 'sv03.5', name: '151' },
    { id: 'swsh3', name: 'Darkness Ablaze', abbreviation: { official: 'DAA' }, tcgOnline: 'DAA' },
  ]);
  const codeMatch = findSetMatch({ setName: 'Darkness Ablaze', setCode: 'DAA' }, index);
  assert.equal(codeMatch.set.id, 'swsh3');
  assert.equal(codeMatch.reason, 'set_code_abbreviation');

  const nameMatch = findSetMatch({ setName: '151', setCode: '' }, index);
  assert.equal(nameMatch.set.id, 'sv03.5');
  assert.equal(nameMatch.reason, 'set_name_exact');
});

test('candidate matching does not require illustrator metadata', () => {
  const row = {
    name: 'Furret',
    setName: 'Darkness Ablaze',
    collectorNumber: '136/189',
    rarity: 'Uncommon',
  };
  const result = bestCandidate(row, [
    {
      id: 'swsh3-136',
      localId: '136',
      name: 'Furret',
      rarity: 'Uncommon',
      category: 'Pokemon',
    },
  ], 'set_name_exact');
  assert.equal(result.status, 'matched');
  assert.equal(result.best.detail.id, 'swsh3-136');
});

test('metadata mapping stores structured scalar and JSON fields', () => {
  const row = {
    blueprintId: '118502',
    name: 'Furret',
    setName: 'Darkness Ablaze',
    collectorNumber: '136/189',
    rarity: 'Uncommon',
  };
  const detail = {
    category: 'Pokemon',
    id: 'swsh3-136',
    localId: '136',
    name: 'Furret',
    set: {
      id: 'swsh3',
      name: 'Darkness Ablaze',
      logo: 'https://assets.tcgdex.net/en/swsh/swsh3/logo',
      symbol: 'https://assets.tcgdex.net/univ/swsh/swsh3/symbol',
      cardCount: { official: 189, total: 201 },
    },
    variants: { normal: true, reverse: true, holo: false, firstEdition: false, wPromo: false },
    hp: 110,
    types: ['Colorless'],
    stage: 'Stage1',
    evolveFrom: 'Sentret',
    attacks: [{ cost: ['Colorless'], name: 'Tail Smash', damage: 90 }],
    weaknesses: [{ type: 'Fighting', value: 'x2' }],
    retreat: 1,
    description: 'It makes a nest.',
    regulationMark: 'D',
    legal: { standard: false, expanded: true },
    updated: '2025-08-16T20:39:55Z',
  };
  const metadata = metadataFromDetail(
    row,
    detail,
    { id: 'swsh3', name: 'Darkness Ablaze', cardCount: { official: 189, total: 201 } },
    { reason: 'set_name_exact', set: { id: 'swsh3', name: 'Darkness Ablaze' } },
    0.98,
    { tcgdexBaseUrl: 'https://api.tcgdex.net', language: 'en' },
  );

  assert.equal(metadata.category, 'Pokemon');
  assert.equal(metadata.setId, 'swsh3');
  assert.equal(metadata.setOfficialCardCount, 189);
  assert.deepEqual(metadata.types, ['Colorless']);
  assert.equal(metadata.hp, 110);
  assert.equal(metadata.regulationMark, 'D');
  assert.equal(metadata.sourceUpdatedAt, '2025-08-16T20:39:55.000Z');
  assert.equal(metadata.rawMetadata.sourceCard.id, 'swsh3-136');
});

test('row parsing and skipping keep metadata separate from main blueprint columns', () => {
  const row = rowFromBlueprint({
    blueprint_id: '118502',
    name: 'Furret',
    set_name: 'Darkness Ablaze',
    card_number: '136/189',
    rarity: 'Uncommon',
    item_kind: 'single',
    product_type: 'card',
  });
  assert.equal(row.blueprintId, '118502');
  assert.equal(row.name, 'Furret');
  assert.equal(shouldSkipBlueprint(row), '');
});

test('upsert SQL targets only the separate metadata table', () => {
  const sql = upsertMetadataSql(1);
  assert.match(sql, /public\.marketplace_blueprint_tcg_metadata/);
  assert.doesNotMatch(sql, /insert into public\.cardtrader_pokemon_blueprints/);
  assert.match(sql, /set_metadata/);
  assert.match(sql, /raw_metadata/);
});

test('missing reasons map to requested counters', () => {
  assert.equal(canonicalReason('not_found', 'card_not_found_in_set'), 'card_not_found');
  assert.equal(canonicalReason('ambiguous', 'ambiguous_set_name_contains'), 'ambiguous_set');
  assert.equal(canonicalReason('not_found', 'low_confidence'), 'low_confidence');
  assert.equal(canonicalReason('skipped', 'missing_collector_number'), 'missing_field');
  assert.equal(canonicalReason('matched', 'set_name_exact'), 'matched');
});
