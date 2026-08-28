const assert = require('node:assert/strict');
const test = require('node:test');

const {
  aggregateNameTokenRows,
  compactName,
  nameTokens,
  normalizedName,
  normalizeSourceRow,
  parseArgs,
  parseLanguages,
  sourceRowsSql,
  upsertNameIndexSql,
  upsertValues,
} = require('./sync-card-name-index-to-supabase');

test('parseArgs defaults to dry-run English sync', () => {
  assert.deepEqual(parseArgs([]), {
    apply: false,
    fullRefresh: false,
    incrementalSince: '',
    languages: ['en'],
    limit: Infinity,
    pageSize: 5000,
    batchSize: 1000,
    transport: 'auto',
  });
});

test('parseArgs supports apply full refresh and language list', () => {
  assert.deepEqual(parseArgs([
    '--apply',
    '--full-refresh',
    '--languages=en,it,fr',
    '--limit=100',
    '--page-size=50',
    '--batch-size=25',
    '--transport=rest',
  ]), {
    apply: true,
    fullRefresh: true,
    incrementalSince: '',
    languages: ['en', 'it', 'fr'],
    limit: 100,
    pageSize: 50,
    batchSize: 25,
    transport: 'rest',
  });
});

test('parseLanguages rejects unsupported languages', () => {
  assert.throws(() => parseLanguages('en,ko'), /Unsupported language/);
});

test('parseLanguages supports TCGdex-backed non-European languages', () => {
  assert.deepEqual(parseLanguages('id,th,zh-cn,zh-tw'), ['id', 'th', 'zh-cn', 'zh-tw']);
});

test('parseArgs rejects unknown sync transports', () => {
  assert.throws(() => parseArgs(['--transport=ftp']), /--transport must be one of/);
});

test('normalizeSourceRow keeps only compact name-index fields', () => {
  const row = normalizeSourceRow({
    card_id: 274416,
    language: 'EN',
    display_name: 'Mew ex',
    canonical_name: 'Mew',
    search_name: 'Mew',
    normalized_name: 'mew',
    compact_name: 'mew',
    name_tokens: ['mew'],
    set_name: 'Paldean Fates',
    card_number: '232/091',
    item_kind: 'single',
    product_type: 'card',
    search_weight: '42.5',
  });

  assert.equal(row.card_id, '274416');
  assert.equal(row.language, 'en');
  assert.equal(row.display_name, 'Mew ex');
  assert.equal(row.compact_name, 'mew');
  assert.deepEqual(row.name_tokens, ['mew']);
  assert.equal(row.search_weight, 42.5);
  assert.equal(row.set_name, 'Paldean Fates');
});

test('sync compact helpers fold accents for Supabase token rows', () => {
  assert.equal(compactName('Pokédex'), 'pokedex');
  assert.equal(normalizedName('Pokémon Flabébé'), 'pokemon flabebe');
  assert.deepEqual(nameTokens('Pokédex Black & White'), ['black', 'pokedex', 'white']);
});

test('aggregateNameTokenRows stores accent-folded compact fields', () => {
  const [aggregated] = aggregateNameTokenRows([
    normalizeSourceRow({
      card_id: 1,
      language: 'en',
      display_name: 'Pokédex',
      canonical_name: 'Pokédex',
      search_name: 'Pokédex',
      normalized_name: 'pokédex',
      compact_name: 'pokédex',
      name_tokens: ['pokédex'],
      set_name: 'Black & White',
      card_number: '98/114',
      search_weight: 10,
    }),
  ]);

  assert.equal(aggregated.normalized_name, 'pokedex');
  assert.equal(aggregated.compact_name, 'pokedex');
  assert.deepEqual(aggregated.name_tokens, ['pokedex']);
});


test('aggregateNameTokenRows stores one row per language and compact search name', () => {
  const rows = [
    normalizeSourceRow({
      card_id: 25,
      language: 'en',
      display_name: 'Pikachu',
      canonical_name: 'Pikachu',
      search_name: 'Pikachu',
      normalized_name: 'pikachu',
      compact_name: 'pikachu',
      name_tokens: ['pikachu'],
      set_name: 'Base Set',
      card_number: '58/102',
      search_weight: 10,
      oracle_updated_at: '2026-05-22T10:00:00Z',
    }),
    normalizeSourceRow({
      card_id: 26,
      language: 'en',
      display_name: 'Pikachu ex',
      canonical_name: 'Pikachu',
      search_name: 'Pikachu',
      normalized_name: 'pikachu',
      compact_name: 'pikachu',
      name_tokens: ['pikachu'],
      set_name: 'Jungle',
      card_number: '60/64',
      search_weight: 25,
      oracle_updated_at: '2026-05-22T11:00:00Z',
    }),
  ];

  const aggregated = aggregateNameTokenRows(rows);

  assert.equal(aggregated.length, 1);
  assert.equal(aggregated[0].language, 'en');
  assert.equal(aggregated[0].search_name, 'Pikachu');
  assert.deepEqual(aggregated[0].card_ids, ['25', '26']);
  assert.equal(aggregated[0].row_count, 2);
  assert.equal(aggregated[0].search_weight, 25);
  assert.deepEqual(aggregated[0].representative_labels.map((label) => label.id), ['25', '26']);
});

test('aggregateNameTokenRows keeps collision-prone Pokemon card names as unique rows', () => {
  const rows = [
    'Giratina',
    'Victini',
    'Dratini',
    'Mantine',
    'Tinkaton',
    'Pincurchin',
    'Darkrai',
    'Darkrai VSTAR',
  ].map((name, index) => normalizeSourceRow({
    card_id: 1000 + index,
    language: 'en',
    display_name: name,
    canonical_name: name,
    search_name: name,
    normalized_name: name.toLowerCase(),
    compact_name: name.toLowerCase().replace(/[^a-z0-9]/g, ''),
    name_tokens: name.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean),
    set_name: 'Pokemon',
    card_number: `${index + 1}/100`,
    item_kind: 'single',
    product_type: 'card',
    search_weight: index,
  }));

  const aggregated = aggregateNameTokenRows(rows);

  assert.deepEqual(
    aggregated.map((row) => row.search_name),
    ['Darkrai', 'Darkrai VSTAR', 'Dratini', 'Giratina', 'Mantine', 'Pincurchin', 'Tinkaton', 'Victini'],
  );
  assert.equal(new Set(aggregated.map((row) => `${row.language}:${row.compact_name}`)).size, aggregated.length);
});

test('aggregateNameTokenRows bounds candidate IDs but keeps representative labels lightweight', () => {
  const rows = Array.from({ length: 540 }, (_, index) => normalizeSourceRow({
    card_id: 2000 + index,
    language: 'en',
    display_name: 'Pikachu',
    canonical_name: 'Pikachu',
    search_name: 'Pikachu',
    normalized_name: 'pikachu',
    compact_name: 'pikachu',
    name_tokens: ['pikachu'],
    set_name: 'Pokemon',
    card_number: `${index + 1}/540`,
    item_kind: 'single',
    product_type: 'card',
    search_weight: index,
  }));

  const [aggregated] = aggregateNameTokenRows(rows);

  assert.equal(aggregated.card_ids.length, 512);
  assert.equal(aggregated.representative_labels.length, 32);
  assert.equal(aggregated.row_count, 512);
});

test('source SQL stores fallback rows under requested language', () => {
  const sql = sourceRowsSql({ incrementalSince: '' });

  assert.match(sql, /from public\.marketplace_cards c/);
  assert.match(sql, /c\.product_type = 'card'/);
  assert.match(sql, /c\.item_kind <> 'product'/);
  assert.match(sql, /left join localized l\s+on l\.name = c\.name/);
  assert.match(sql, /from public\.marketplace_card_name_translations translations/);
  assert.match(sql, /translations\.language = \$1::text/);
  assert.match(sql, /select distinct on \(c\.card_id, \$1::text, coalesce\(nullif\(l\.localized_name, ''\), c\.name\)\)/);
  assert.match(sql, /\$1::text as language/);
  assert.doesNotMatch(sql, /distinct on \(c\.card_id, l\.language, l\.localized_name\)/);
  assert.doesNotMatch(sql, /from public\.marketplace_search_candidates c/);
  assert.doesNotMatch(sql, /from public\.cardtrader_pokemon_blueprints b/);
});

test('source SQL excludes obvious products without broad Pokemon-name token filters', () => {
  const sql = sourceRowsSql({ incrementalSince: '' });

  assert.match(sql, /c\.product_type = 'card'/);
  assert.match(sql, /lower\(concat_ws\(' ', c\.name, c\.card_type, c\.rarity, c\.set_name\)\) !~/);
  assert.match(sql, /build & battle/);
  assert.match(sql, /center set/);
  assert.match(sql, /special set/);
  assert.match(sql, /booster/);
  assert.match(sql, /tin/);
  assert.doesNotMatch(sql, /Giratina|Victini|Dratini|Mantine|Tinkaton|Pincurchin/);
  assert.doesNotMatch(sql, /name ~ '\(booster\|tin\|box\|accessory\)'/);
});

test('upsert SQL targets Supabase name index only', () => {
  const sql = upsertNameIndexSql(2);

  assert.match(sql, /insert into public\.marketplace_card_name_tokens/);
  assert.match(sql, /on conflict \(language, search_name\) do update/);
  assert.match(sql, /card_ids = excluded\.card_ids/);
  assert.doesNotMatch(sql, /marketplace_user_listings|marketplace_blueprint_price|firebase_users/);
});

test('upsertValues serializes rows in SQL column order', () => {
  const aggregated = aggregateNameTokenRows([
    normalizeSourceRow({
      card_id: 25,
      language: 'en',
      display_name: 'Pikachu',
      canonical_name: 'Pikachu',
      search_name: 'Pikachu',
      normalized_name: 'pikachu',
      compact_name: 'pikachu',
      name_tokens: ['pikachu'],
      set_name: 'Base Set',
      card_number: '58/102',
      search_weight: 100,
    }),
  ]);
  const aggregatedValues = upsertValues(aggregated);

  assert.deepEqual(aggregatedValues.slice(0, 11), [
    'en',
    'Pikachu',
    'Pikachu',
    ['Pikachu'],
    'Pikachu',
    'pikachu',
    'pikachu',
    ['pikachu'],
    ['25'],
    aggregated[0].representative_labels,
    1,
  ]);
});

test('sync script apply env can use Supabase pooler URL', () => {
  const script = require('node:fs').readFileSync(
    require('node:path').join(__dirname, 'sync-card-name-index-to-supabase.js'),
    'utf8',
  );

  assert.match(script, /SUPABASE_NAME_INDEX_DATABASE_URL/);
  assert.match(script, /SUPABASE_DB_POOLER_URL/);
  assert.match(script, /SUPABASE_DB_URL/);
});
