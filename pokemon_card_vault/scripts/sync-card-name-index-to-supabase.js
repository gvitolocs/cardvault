#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const DEFAULT_BATCH_SIZE = 1000;
const DEFAULT_PAGE_SIZE = 5000;
const SUPPORTED_LANGUAGES = ['en', 'it', 'fr', 'de', 'es', 'pt', 'id', 'th', 'ja', 'zh-cn', 'zh-tw'];
const TARGET_TABLE = 'marketplace_card_name_tokens';
const REPRESENTATIVE_LABEL_LIMIT = 32;
const CARD_ID_LIMIT = 512;
const OBVIOUS_PRODUCT_NAME_PATTERN = [
  'booster',
  'booster box',
  'booster bundle',
  'box',
  'build & battle',
  'build and battle',
  'bundle',
  'center set',
  'collection',
  'collection box',
  'collector chest',
  'collector\\.?s? chest',
  'deck',
  'elite trainer box',
  'etb',
  'gift box',
  'pin collection',
  'playmat',
  'portfolio',
  'premium collection',
  'sleeves?',
  'special collection',
  'special set',
  'tin',
  'tins',
].join('|');

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadLocalEnv() {
  const envPath = path.join(ROOT_DIR, '.env.local');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function parseLanguages(value) {
  const languages = String(value || 'en')
    .split(',')
    .map((language) => language.trim().toLowerCase())
    .filter(Boolean);
  const unique = [...new Set(languages)];
  for (const language of unique) {
    if (!SUPPORTED_LANGUAGES.includes(language)) {
      throw new Error(`Unsupported language "${language}". Use one of: ${SUPPORTED_LANGUAGES.join(', ')}.`);
    }
  }
  return unique.length > 0 ? unique : ['en'];
}

function parseArgs(argv) {
  const options = {
    apply: false,
    fullRefresh: false,
    incrementalSince: '',
    languages: ['en'],
    limit: Infinity,
    pageSize: DEFAULT_PAGE_SIZE,
    batchSize: DEFAULT_BATCH_SIZE,
    transport: 'auto',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--full-refresh') {
      options.fullRefresh = true;
    } else if (arg.startsWith('--incremental-since=')) {
      options.incrementalSince = arg.slice('--incremental-since='.length).trim();
    } else if (arg.startsWith('--languages=')) {
      options.languages = parseLanguages(arg.slice('--languages='.length));
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? Infinity : Number(raw);
    } else if (arg.startsWith('--page-size=')) {
      options.pageSize = Number(arg.slice('--page-size='.length));
    } else if (arg.startsWith('--batch-size=')) {
      options.batchSize = Number(arg.slice('--batch-size='.length));
    } else if (arg.startsWith('--transport=')) {
      options.transport = arg.slice('--transport='.length).trim().toLowerCase();
    }
  }
  if (!Number.isFinite(options.limit) && options.limit !== Infinity) {
    throw new Error('--limit must be a number or all.');
  }
  if (!Number.isSafeInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 10_000) {
    throw new Error('--page-size must be between 1 and 10000.');
  }
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 5000) {
    throw new Error('--batch-size must be between 1 and 5000.');
  }
  if (options.fullRefresh && options.incrementalSince) {
    throw new Error('Use either --full-refresh or --incremental-since, not both.');
  }
  if (!['auto', 'postgres', 'rest'].includes(options.transport)) {
    throw new Error('--transport must be one of: auto, postgres, rest.');
  }
  return options;
}

function createPoolFromEnv(envNames, label, sslVerifyEnv = 'MARKETPLACE_DATABASE_SSL_VERIFY') {
  const connectionString = envNames.map((name) => process.env[name]).find(Boolean);
  if (!connectionString) {
    throw new Error(`${envNames.join(' or ')} is required for ${label}.`);
  }
  const sslVerify = process.env[sslVerifyEnv] === '1';
  const sanitizedConnectionString = sslVerify
    ? connectionString
    : connectionString.replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
        prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '',
      ).replace(/[?&]$/, '');
  return new Pool({
    connectionString: sanitizedConnectionString,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: sslVerify },
  });
}

function sourceRowsSql({ incrementalSince }) {
  const productNamePattern = OBVIOUS_PRODUCT_NAME_PATTERN.replaceAll("'", "''");
  return `
    with cards as (
      select
        c.card_id,
        c.name,
        coalesce(nullif(c.source_name, ''), c.name) as source_name,
        coalesce(nullif(c.display_name, ''), c.name) as display_name,
        coalesce(nullif(c.canonical_name, ''), c.name) as source_canonical_name,
        c.set_name,
        c.card_number,
        c.product_variant,
        c.rarity,
        c.card_type,
        c.item_kind,
        c.product_type,
        c.trainer_name,
        c.emoji,
        (
          case when c.rarity ilike '%rare%' then 8 else 0 end +
          case when c.name ~* '(^|[^a-z0-9])(ex|vmax|vstar|gx|lv\\.x)([^a-z0-9]|$)' then 10 else 0 end +
          case when c.card_number ~ '/' then 10 else 0 end +
          case when c.trainer_name <> '' then 6 else 0 end +
          case when c.preview_image_url is not null then 4 else 0 end
        )::real as search_weight,
        c.imported_at as oracle_updated_at
      from public.marketplace_cards c
      where c.name <> ''
        and c.item_kind <> 'product'
        and c.product_type = 'card'
        and lower(concat_ws(' ', c.name, c.card_type, c.rarity, c.set_name)) !~ '(^|[^a-z0-9])(${productNamePattern})([^a-z0-9]|$)'
        and coalesce(c.preview_image_url, c.cdn_image_url, c.image_url) is not null
        and (
          $2::timestamptz is null
          or c.imported_at >= $2::timestamptz
        )
    ),
    localized as (
      select
        names.language,
        names.name,
        names.localized_name,
        names.normalized_name,
        names.compact_name,
        names.name_tokens,
        names.source,
        names.source_card_id,
        names.updated_at
      from public.marketplace_card_names_for_language($1::text) names
      union all
      select
        translations.language,
        translations.name,
        translations.localized_name,
        translations.normalized_localized_name as normalized_name,
        translations.compact_localized_name as compact_name,
        translations.localized_name_tokens as name_tokens,
        translations.source,
        translations.source_card_id,
        translations.updated_at
      from public.marketplace_card_name_translations translations
      where translations.language = $1::text
    )
    select distinct on (c.card_id, $1::text, coalesce(nullif(l.localized_name, ''), c.name))
      c.card_id,
      $1::text as language,
      c.display_name,
      coalesce(nullif(l.localized_name, ''), c.name) as canonical_name,
      coalesce(nullif(l.localized_name, ''), c.name) as search_name,
      coalesce(nullif(l.normalized_name, ''), public.marketplace_search_normalize(c.name)) as normalized_name,
      coalesce(nullif(l.compact_name, ''), public.marketplace_search_compact(c.name)) as compact_name,
      coalesce(l.name_tokens, public.marketplace_search_tokenize(c.name)) as name_tokens,
      c.set_name,
      c.card_number,
      c.product_variant,
      c.rarity,
      c.card_type,
      c.item_kind,
      c.product_type,
      c.trainer_name,
      c.emoji,
      c.search_weight::real as search_weight,
      c.oracle_updated_at
    from cards c
    left join localized l
      on l.name = c.name
    where coalesce(nullif(l.compact_name, ''), public.marketplace_search_compact(c.name)) <> ''
    order by c.card_id, $1::text, coalesce(nullif(l.localized_name, ''), c.name), c.search_weight desc
    limit $3::integer
    offset $4::integer
  `;
}

function normalizeSourceRow(row) {
  return {
    card_id: String(row.card_id || '').trim(),
    language: String(row.language || 'en').trim().toLowerCase(),
    display_name: String(row.display_name || '').trim(),
    canonical_name: String(row.canonical_name || row.display_name || '').trim(),
    search_name: String(row.search_name || row.canonical_name || row.display_name || '').trim(),
    normalized_name: String(row.normalized_name || '').trim(),
    compact_name: String(row.compact_name || '').trim(),
    name_tokens: Array.isArray(row.name_tokens) ? row.name_tokens.map(String) : [],
    set_name: String(row.set_name || '').trim(),
    card_number: String(row.card_number || '').trim(),
    product_variant: String(row.product_variant || '').trim(),
    rarity: String(row.rarity || '').trim(),
    card_type: String(row.card_type || '').trim(),
    item_kind: String(row.item_kind || 'single').trim() || 'single',
    product_type: String(row.product_type || '').trim(),
    trainer_name: String(row.trainer_name || '').trim(),
    emoji: String(row.emoji || '').trim(),
    search_weight: Number(row.search_weight || 0),
    oracle_updated_at: row.oracle_updated_at || null,
  };
}

function labelForSourceRow(row) {
  return {
    id: row.card_id,
    name: row.display_name || row.search_name,
    item_kind: row.item_kind || 'single',
    product_type: row.product_type || 'card',
    set_name: row.set_name || '',
    card_number: row.card_number || '',
    rarity: row.rarity || '',
    product_variant: row.product_variant || '',
    trainer_name: row.trainer_name || '',
  };
}

function sourceRowSort(left, right, searchName = '') {
  const compactSearchName = compactName(searchName);
  const exactDisplayDiff =
    Number(compactName(right.display_name) === compactSearchName) -
    Number(compactName(left.display_name) === compactSearchName);
  if (exactDisplayDiff !== 0) return exactDisplayDiff;
  const displayCanonicalDiff =
    Number(compactName(right.display_name) === compactName(right.canonical_name)) -
    Number(compactName(left.display_name) === compactName(left.canonical_name));
  if (displayCanonicalDiff !== 0) return displayCanonicalDiff;
  return Number(right.search_weight || 0) - Number(left.search_weight || 0) ||
    String(left.display_name || '').localeCompare(String(right.display_name || '')) ||
    String(left.card_number || '').localeCompare(String(right.card_number || '')) ||
    String(left.card_id || '').localeCompare(String(right.card_id || ''));
}

function foldDiacritics(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '');
}

function compactName(value) {
  return foldDiacritics(value).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function normalizedName(value) {
  return foldDiacritics(value).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function nameTokens(value) {
  return [...new Set(normalizedName(value).split(/\s+/).filter((token) =>
    token &&
    (token.length >= 2 || token === 'v' || /^[0-9]+$/.test(token))))].sort();
}

function normalizeSearchFields(row) {
  const sourceName = row.search_name || row.canonical_name || row.display_name;
  return {
    ...row,
    normalized_name: normalizedName(sourceName),
    compact_name: compactName(sourceName),
    name_tokens: nameTokens(sourceName),
  };
}

function aggregateNameTokenRows(rows) {
  const groups = new Map();
  for (const rawRow of rows || []) {
    const row = normalizeSearchFields(rawRow);
    if (!row.language || !row.search_name || !row.compact_name || !row.card_id) continue;
    const key = `${row.language}\0${row.compact_name}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return [...groups.values()].map((group) => {
    const sorted = [...group].sort((left, right) => sourceRowSort(left, right, group[0]?.search_name));
    const best = sorted[0];
    const seenIds = new Set();
    const cardIds = [];
    const labels = [];
    const canonicalNames = [];
    const seenCanonicalNames = new Set();
    for (const row of sorted) {
      if (!seenIds.has(row.card_id)) {
        seenIds.add(row.card_id);
        if (cardIds.length < CARD_ID_LIMIT) {
          cardIds.push(row.card_id);
        }
        if (labels.length < REPRESENTATIVE_LABEL_LIMIT) {
          labels.push(labelForSourceRow(row));
        }
      }
      const canonicalName = row.canonical_name || row.display_name || row.search_name;
      if (canonicalName && !seenCanonicalNames.has(canonicalName)) {
        seenCanonicalNames.add(canonicalName);
        canonicalNames.push(canonicalName);
      }
    }
    return {
      language: best.language,
      display_name: best.search_name,
      canonical_name: best.canonical_name || best.display_name || best.search_name,
      canonical_names: canonicalNames,
      search_name: best.search_name,
      normalized_name: best.normalized_name,
      compact_name: best.compact_name,
      name_tokens: best.name_tokens,
      card_ids: cardIds,
      representative_labels: labels,
      row_count: cardIds.length,
      search_weight: Math.max(...sorted.map((row) => Number(row.search_weight || 0))),
      oracle_updated_at: sorted
        .map((row) => row.oracle_updated_at)
        .filter(Boolean)
        .sort()
        .at(-1) || null,
    };
  }).sort((left, right) =>
    left.language.localeCompare(right.language) ||
    left.search_name.localeCompare(right.search_name));
}

function upsertNameIndexSql(rowCount) {
  const columns = [
    'language',
    'display_name',
    'canonical_name',
    'canonical_names',
    'search_name',
    'normalized_name',
    'compact_name',
    'name_tokens',
    'card_ids',
    'representative_labels',
    'row_count',
    'search_weight',
    'oracle_updated_at',
  ];
  const rows = [];
  let parameter = 1;
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const placeholders = [];
    for (let columnIndex = 0; columnIndex < columns.length; columnIndex += 1) {
      placeholders.push(`$${parameter}`);
      parameter += 1;
    }
    rows.push(`(${placeholders.join(', ')})`);
  }
  return `
    insert into public.${TARGET_TABLE} (${columns.join(', ')})
    values ${rows.join(', ')}
    on conflict (language, search_name) do update set
      display_name = excluded.display_name,
      canonical_name = excluded.canonical_name,
      canonical_names = excluded.canonical_names,
      normalized_name = excluded.normalized_name,
      compact_name = excluded.compact_name,
      name_tokens = excluded.name_tokens,
      card_ids = excluded.card_ids,
      representative_labels = excluded.representative_labels,
      row_count = excluded.row_count,
      search_weight = excluded.search_weight,
      oracle_updated_at = excluded.oracle_updated_at,
      synced_at = now(),
      updated_at = now()
  `;
}

function upsertValues(rows) {
  return rows.flatMap((row) => [
    row.language,
    row.display_name,
    row.canonical_name,
    row.canonical_names,
    row.search_name,
    row.normalized_name,
    row.compact_name,
    row.name_tokens,
    row.card_ids,
    row.representative_labels,
    row.row_count,
    row.search_weight,
    row.oracle_updated_at,
  ]);
}

function supabaseRestConfig() {
  const url = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const key = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '');
  if (!url || !key) return null;
  return { url, key };
}

async function supabaseRestRequest(pathname, options = {}) {
  const config = supabaseRestConfig();
  if (!config) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for REST transport.');
  }
  const response = await fetch(`${config.url}${pathname}`, {
    method: options.method || 'GET',
    headers: {
      apikey: config.key,
      Authorization: `Bearer ${config.key}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Supabase REST request failed ${response.status}: ${body.slice(0, 300)}`);
  }
  const countHeader = response.headers.get('content-range');
  const count = countHeader && countHeader.includes('/')
    ? Number(countHeader.split('/').at(-1))
    : null;
  if (response.status === 204) return null;
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  return options.includeCount ? { data, count: Number.isFinite(count) ? count : 0 } : data;
}

async function fetchSourceRows(oraclePool, language, options, offset) {
  const remaining = options.limit === Infinity ? options.pageSize : options.limit - offset;
  if (remaining <= 0) return [];
  const result = await oraclePool.query(
    sourceRowsSql({ incrementalSince: options.incrementalSince }),
    [
      language,
      options.incrementalSince || null,
      Math.min(options.pageSize, remaining),
      offset,
    ],
  );
  return result.rows.map(normalizeSourceRow).filter((row) => row.card_id && row.compact_name);
}

async function upsertRows(pool, rows, batchSize) {
  let upserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    await pool.query(upsertNameIndexSql(batch.length), upsertValues(batch));
    upserted += batch.length;
  }
  return upserted;
}

async function upsertRowsRest(rows, batchSize) {
  let upserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    await supabaseRestRequest(
      `/rest/v1/${TARGET_TABLE}?on_conflict=language,search_name`,
      {
        method: 'POST',
        headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: batch,
      },
    );
    upserted += batch.length;
  }
  return upserted;
}

async function truncateSupabaseIndex(pool, languages) {
  await pool.query(
    `delete from public.${TARGET_TABLE} where language = any($1::text[])`,
    [languages],
  );
}

async function truncateSupabaseIndexRest(languages) {
  for (const language of languages) {
    await supabaseRestRequest(
      `/rest/v1/${TARGET_TABLE}?language=eq.${encodeURIComponent(language)}`,
      {
        method: 'DELETE',
        headers: { Prefer: 'return=minimal' },
      },
    );
  }
}

async function syncCardNameIndex({ oraclePool, supabasePool, options }) {
  const counts = {
    fetched: 0,
    upserted: 0,
    languages: {},
  };
  const useRest = options.transport === 'rest';
  await oraclePool.query('set statement_timeout = 0');
  await oraclePool.query('set idle_in_transaction_session_timeout = 0');
  if (supabasePool) {
    await supabasePool.query('set statement_timeout = 0');
    await supabasePool.query('set idle_in_transaction_session_timeout = 0');
  }
  if (options.apply && options.fullRefresh && useRest) {
    await truncateSupabaseIndexRest(options.languages);
  } else if (options.apply && options.fullRefresh) {
    await truncateSupabaseIndex(supabasePool, options.languages);
  }
  if (options.incrementalSince) {
    throw new Error('Incremental apply is disabled for the unique-name index; run --full-refresh so each name row contains all card_ids.');
  }
  for (const language of options.languages) {
    let offset = 0;
    const languageRows = [];
    counts.languages[language] = { fetched: 0, uniqueNames: 0, upserted: 0 };
    while (offset < options.limit) {
      const rows = await fetchSourceRows(oraclePool, language, options, offset);
      if (rows.length === 0) break;
      counts.fetched += rows.length;
      counts.languages[language].fetched += rows.length;
      languageRows.push(...rows);
      offset += rows.length;
      if (rows.length < options.pageSize || options.limit !== Infinity && offset >= options.limit) break;
    }
    const aggregatedRows = aggregateNameTokenRows(languageRows);
    counts.languages[language].uniqueNames = aggregatedRows.length;
    if (options.apply && useRest) {
      const upserted = await upsertRowsRest(aggregatedRows, options.batchSize);
      counts.upserted += upserted;
      counts.languages[language].upserted += upserted;
    } else if (options.apply) {
      const upserted = await upsertRows(supabasePool, aggregatedRows, options.batchSize);
      counts.upserted += upserted;
      counts.languages[language].upserted += upserted;
    }
  }
  return counts;
}

async function verifySupabase(pool, languages) {
  const result = await pool.query(
    `
      select language, count(*)::integer as rows, max(synced_at) as last_synced_at
      from public.${TARGET_TABLE}
      where language = any($1::text[])
      group by language
      order by language
    `,
    [languages],
  );
  return result.rows;
}

async function verifySupabaseRest(languages) {
  const results = [];
  for (const language of languages) {
    const rows = await supabaseRestRequest(
      `/rest/v1/${TARGET_TABLE}?select=synced_at&language=eq.${encodeURIComponent(language)}&order=synced_at.desc&limit=1`,
      { headers: { Prefer: 'count=exact' } },
    );
    const countResult = await supabaseRestRequest(
      `/rest/v1/${TARGET_TABLE}?select=language&language=eq.${encodeURIComponent(language)}&limit=1`,
      { headers: { Prefer: 'count=exact' }, includeCount: true },
    );
    results.push({
      language,
      rows: countResult.count,
      last_synced_at: rows?.[0]?.synced_at || null,
    });
  }
  return results;
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const oraclePool = createPoolFromEnv(
    ['MARKETPLACE_NAME_SEARCH_DATABASE_URL', 'MARKETPLACE_DATABASE_URL'],
    'Oracle marketplace source',
  );
  const supabasePool = options.apply && options.transport !== 'rest'
    ? createPoolFromEnv(
      ['SUPABASE_NAME_INDEX_DATABASE_URL', 'SUPABASE_DB_POOLER_URL', 'SUPABASE_DB_URL'],
      'Supabase name index',
      'SUPABASE_NAME_INDEX_DATABASE_SSL_VERIFY',
    )
    : null;
  try {
    const counts = await syncCardNameIndex({ oraclePool, supabasePool, options });
    const result = {
      mode: options.apply ? 'apply' : 'dry-run',
      source: 'oracle:marketplace_cards + marketplace_card_names_for_language',
      target: `supabase:${TARGET_TABLE}`,
      transport: options.apply ? options.transport : 'dry-run',
      fullRefresh: options.fullRefresh,
      incrementalSince: options.incrementalSince || null,
      languages: options.languages,
      counts,
    };
    if (options.apply) {
      result.supabase = options.transport === 'rest'
        ? await verifySupabaseRest(options.languages)
        : await verifySupabase(supabasePool, options.languages);
    }
    console.log(JSON.stringify(result, null, 2));
    if (!options.apply) {
      console.log(`Dry run only; pass --apply after creating public.${TARGET_TABLE} to upsert unique name-token rows.`);
    }
  } finally {
    await oraclePool.end().catch(() => {});
    await supabasePool?.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  parseArgs,
  parseLanguages,
  aggregateNameTokenRows,
  normalizeSourceRow,
  sourceRowsSql,
  upsertNameIndexSql,
  upsertValues,
  compactName,
  normalizedName,
  nameTokens,
};
