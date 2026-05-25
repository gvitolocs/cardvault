#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const CARDTRADER_API_BASE = 'https://api.cardtrader.com/api/v2';
const BLUEPRINT_COLUMNS = [
  'id',
  'name',
  'version',
  'game_id',
  'category_id',
  'expansion_id',
  'image_url',
  'card_market_ids',
  'tcg_player_ids',
  'editable_properties',
  'blueprint',
  'expansion',
];
const JSON_COLUMNS = new Set([
  'card_market_ids',
  'tcg_player_ids',
  'editable_properties',
  'blueprint',
  'expansion',
]);

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

function loadEnv(filePath = path.join(ROOT_DIR, '.env.local')) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function parseCsv(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseArgs(argv) {
  const options = {
    apply: false,
    input: '',
    streamAll: false,
    expansionIds: [],
    expansionNames: [],
    limit: Infinity,
    batchSize: 500,
    sleepMs: 100,
    images: false,
    refresh: false,
    syncSupabase: false,
    languages: 'en',
    supabaseTransport: 'rest',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--stream-all') {
      options.streamAll = true;
    } else if (arg.startsWith('--input=')) {
      options.input = arg.slice('--input='.length).trim();
    } else if (arg.startsWith('--expansion-ids=')) {
      options.expansionIds = parseCsv(arg.slice('--expansion-ids='.length))
        .filter((value) => /^\d+$/.test(value))
        .map(Number);
    } else if (arg.startsWith('--expansion-names=')) {
      options.expansionNames = parseCsv(arg.slice('--expansion-names='.length));
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? Infinity : Number(raw);
    } else if (arg.startsWith('--batch-size=')) {
      options.batchSize = Number(arg.slice('--batch-size='.length));
    } else if (arg.startsWith('--sleep-ms=')) {
      options.sleepMs = Number(arg.slice('--sleep-ms='.length));
    } else if (arg === '--images') {
      options.images = true;
    } else if (arg === '--refresh') {
      options.refresh = true;
    } else if (arg === '--sync-supabase') {
      options.syncSupabase = true;
    } else if (arg.startsWith('--languages=')) {
      options.languages = arg.slice('--languages='.length).trim() || 'en';
    } else if (arg.startsWith('--supabase-transport=')) {
      options.supabaseTransport = arg.slice('--supabase-transport='.length).trim() || 'rest';
    }
  }
  if (!Number.isFinite(options.limit) && options.limit !== Infinity) {
    throw new Error('--limit must be a number or all.');
  }
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 5000) {
    throw new Error('--batch-size must be between 1 and 5000.');
  }
  if (!Number.isSafeInteger(options.sleepMs) || options.sleepMs < 0 || options.sleepMs > 10_000) {
    throw new Error('--sleep-ms must be between 0 and 10000.');
  }
  if (!options.input && !options.streamAll && options.expansionIds.length === 0 && options.expansionNames.length === 0) {
    throw new Error('Use --stream-all, --expansion-ids, --expansion-names, or --input for a bounded delta import.');
  }
  return options;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function createMarketplacePool() {
  return new Pool({
    connectionString: requireEnv('MARKETPLACE_DATABASE_URL'),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
  });
}

async function sleep(ms) {
  if (ms > 0) await new Promise((resolve) => setTimeout(resolve, ms));
}

function asList(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.array)) return payload.array;
  throw new Error(`Unexpected CardTrader response shape: ${typeof payload}`);
}

async function cardtraderGet(apiPath, params = {}) {
  const url = new URL(`${CARDTRADER_API_BASE}${apiPath}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${requireEnv('CARDTRADER_AUTH_TOKEN')}`,
      Accept: 'application/json',
      'User-Agent': 'pokoin-cardtrader-delta-import/1.0',
    },
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) {
    throw new Error(`CardTrader ${apiPath} failed: HTTP ${response.status}: ${await response.text()}`);
  }
  return asList(await response.json());
}

function findPokemonGame(games) {
  const match = games.find((game) => {
    const haystack = `${game.name || ''} ${game.display_name || ''}`.toLowerCase();
    return haystack.includes('pokemon') || haystack.includes('pokémon');
  });
  if (!match) throw new Error('Could not find Pokemon game in CardTrader /games response.');
  return match;
}

function normalizeName(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

async function resolveExpansions({ streamAll, expansionIds, expansionNames }) {
  const games = await cardtraderGet('/games');
  const pokemon = findPokemonGame(games);
  const expansions = (await cardtraderGet('/expansions'))
    .filter((expansion) => Number(expansion.game_id) === Number(pokemon.id));
  if (streamAll) {
    return expansions.sort((a, b) => Number(a.id) - Number(b.id));
  }
  const ids = new Set(expansionIds);
  const nameNeedles = expansionNames.map(normalizeName).filter(Boolean);
  for (const expansion of expansions) {
    const normalized = normalizeName(expansion.name);
    if (nameNeedles.some((needle) => normalized === needle || normalized.includes(needle))) {
      ids.add(Number(expansion.id));
    }
  }
  const selected = expansions.filter((expansion) => ids.has(Number(expansion.id)));
  const missingNames = expansionNames.filter((name) => {
    const needle = normalizeName(name);
    return !selected.some((expansion) => normalizeName(expansion.name).includes(needle));
  });
  if (missingNames.length > 0) {
    throw new Error(`Could not resolve CardTrader expansion names: ${missingNames.join(', ')}`);
  }
  return selected.sort((a, b) => Number(a.id) - Number(b.id));
}

async function fetchExpansionRecords(expansions, { sleepMs, limit }) {
  const records = [];
  for (const [index, expansion] of expansions.entries()) {
    const blueprints = await cardtraderGet('/blueprints/export', { expansion_id: expansion.id });
    for (const blueprint of blueprints) {
      records.push({ blueprint, expansion, game: { id: expansion.game_id, name: 'Pokémon', display_name: 'Pokémon' } });
      if (records.length >= limit) return records;
    }
    if (index < expansions.length - 1) await sleep(sleepMs);
  }
  return records;
}

function createRunSummary({ mode, source }) {
  return {
    mode,
    source,
    counts: {
      fetched: 0,
      existingRaw: 0,
      existingSearchCandidates: 0,
      missingImagesForNewOrUnprojectedRows: 0,
      missingRaw: 0,
      existingRawMissingSearchCandidate: 0,
      inserted: 0,
    },
    missingSamples: [],
    existingRawMissingSearchCandidateSamples: [],
    imageIds: [],
    expansionProgress: [],
  };
}

function mergeSamples(target, rows) {
  for (const sample of summarizeRows(rows)) {
    if (target.length >= 25) break;
    target.push(sample);
  }
}

async function analyzeRows(pool, rows, { apply, batchSize, collectImages }) {
  const ids = rows.map((row) => row.id);
  const rawExisting = await existingIdSet(pool, ids);
  const candidateExisting = await existingIdSet(pool, ids, 'marketplace_search_candidates', 'card_id');
  const missingRows = rows.filter((row) => !rawExisting.has(String(row.id)));
  const existingRawMissingCandidate = rows.filter((row) =>
    rawExisting.has(String(row.id)) && !candidateExisting.has(String(row.id)));
  const recoveryImageIds = existingRawMissingCandidate.map((row) => row.id);
  const imageNeeded = collectImages
    ? await imageNeededIdSet(pool, [...missingRows.map((row) => row.id), ...recoveryImageIds])
    : new Set();
  const inserted = apply ? await insertMissingRows(pool, missingRows, batchSize) : 0;
  const insertedIdSet = new Set(missingRows.map((row) => String(row.id)));
  const imageIds = rows
    .filter((row) => insertedIdSet.has(String(row.id)) || imageNeeded.has(String(row.id)))
    .map((row) => row.id);

  return {
    ids,
    rawExisting,
    candidateExisting,
    imageNeeded,
    missingRows,
    existingRawMissingCandidate,
    inserted,
    imageIds,
  };
}

function readInputRecords(inputPath, options) {
  const fullPath = path.resolve(ROOT_DIR, inputPath);
  const expansionIds = new Set(options.expansionIds.map(Number));
  const expansionNameNeedles = options.expansionNames.map(normalizeName).filter(Boolean);
  const records = [];
  for (const line of fs.readFileSync(fullPath, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue;
    const record = JSON.parse(line);
    const expansion = record.expansion || {};
    const expansionId = Number(record.blueprint?.expansion_id || expansion.id || expansion.expansion_id);
    const expansionName = normalizeName(expansion.name || record.blueprint?.expansion_name);
    if (expansionIds.size > 0 && !expansionIds.has(expansionId)) continue;
    if (
      expansionNameNeedles.length > 0 &&
      !expansionNameNeedles.some((needle) => expansionName === needle || expansionName.includes(needle))
    ) {
      continue;
    }
    records.push(record);
    if (records.length >= options.limit) break;
  }
  return records;
}

function tcgPlayerIds(blueprint) {
  if (Array.isArray(blueprint.tcg_player_ids)) return blueprint.tcg_player_ids;
  if (blueprint.tcg_player_id == null || blueprint.tcg_player_id === '') return null;
  return [blueprint.tcg_player_id];
}

function rowFromRecord(record) {
  const blueprint = record.blueprint || {};
  return {
    id: blueprint.id,
    name: blueprint.name || '',
    version: blueprint.version ?? null,
    game_id: blueprint.game_id,
    category_id: blueprint.category_id ?? null,
    expansion_id: blueprint.expansion_id ?? record.expansion?.id ?? null,
    image_url: blueprint.image_url || null,
    card_market_ids: blueprint.card_market_ids ?? null,
    tcg_player_ids: tcgPlayerIds(blueprint),
    editable_properties: blueprint.editable_properties || [],
    blueprint,
    expansion: record.expansion || null,
  };
}

function uniqueRecords(records) {
  const seen = new Set();
  const rows = [];
  for (const record of records) {
    const row = rowFromRecord(record);
    if (!row.id || seen.has(String(row.id))) continue;
    seen.add(String(row.id));
    rows.push(row);
  }
  return rows;
}

async function existingIdSet(pool, ids, tableName = 'cardtrader_pokemon_blueprints', columnName = 'id') {
  if (ids.length === 0) return new Set();
  const result = await pool.query(
    `select ${columnName}::text as id from public.${tableName} where ${columnName} = any($1::bigint[])`,
    [ids],
  );
  return new Set(result.rows.map((row) => row.id));
}

async function imageNeededIdSet(pool, ids) {
  if (ids.length === 0) return new Set();
  const result = await pool.query(
    `
      select id::text
      from public.cardtrader_pokemon_blueprints
      where id = any($1::bigint[])
        and (
          coalesce(cdn_image_url, '') = ''
          or coalesce(preview_image_url, '') = ''
          or coalesce(homepage_image_url, '') = ''
        )
    `,
    [ids],
  );
  return new Set(result.rows.map((row) => row.id));
}

function insertMissingSql(rowCount) {
  const placeholders = [];
  let parameter = 1;
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const row = [];
    for (const column of BLUEPRINT_COLUMNS) {
      const cast = JSON_COLUMNS.has(column) ? '::jsonb' : '';
      row.push(`$${parameter}${cast}`);
      parameter += 1;
    }
    placeholders.push(`(${row.join(', ')})`);
  }
  return `
    insert into public.cardtrader_pokemon_blueprints (${BLUEPRINT_COLUMNS.join(', ')})
    values ${placeholders.join(', ')}
    on conflict (id) do nothing
  `;
}

function insertValues(rows) {
  return rows.flatMap((row) =>
    BLUEPRINT_COLUMNS.map((column) =>
      JSON_COLUMNS.has(column) ? JSON.stringify(row[column] ?? null) : row[column] ?? null,
    ),
  );
}

async function insertMissingRows(pool, rows, batchSize) {
  let inserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    const result = await pool.query(insertMissingSql(batch.length), insertValues(batch));
    inserted += result.rowCount;
  }
  return inserted;
}

function summarizeRows(rows) {
  return rows.slice(0, 25).map((row) => ({
    id: row.id,
    name: row.name,
    version: row.version,
    expansion_id: row.expansion_id,
    expansion_name: row.expansion?.name || '',
    image: Boolean(row.blueprint?.image?.url || row.blueprint?.image_url || row.image_url),
  }));
}

function ensureImageEnv() {
  for (const key of ['CLOUDFLARE_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY']) {
    requireEnv(key);
  }
}

function runNodeScript(args, env = process.env) {
  const result = spawnSync(process.execPath, args, {
    cwd: ROOT_DIR,
    env,
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error(`${args.join(' ')} failed with exit code ${result.status}`);
  }
}

function chunkArray(values, size) {
  const chunks = [];
  for (let offset = 0; offset < values.length; offset += size) {
    chunks.push(values.slice(offset, offset + size));
  }
  return chunks;
}

function runImagePipeline(ids, { apply }) {
  if (ids.length === 0) return { skipped: 'no_ids' };
  const chunks = chunkArray(ids, Number(process.env.CARDTRADER_DELTA_IMAGE_CHUNK_SIZE || 50));
  if (!apply) {
    return {
      wouldRun: chunks.flatMap((chunk) => {
        const idList = chunk.join(',');
        return [
          `ORACLE_IMAGE_IDS=${idList} node scripts/import-oracle-cardtrader-images.js`,
          `node scripts/generate-oracle-homepage-card-images.js --ids=${idList} --limit=all`,
        ];
      }),
    };
  }
  ensureImageEnv();
  for (const chunk of chunks) {
    const idList = chunk.join(',');
    runNodeScript(['scripts/import-oracle-cardtrader-images.js'], {
      ...process.env,
      ORACLE_IMAGE_IDS: idList,
      ORACLE_IMAGE_BATCH_SIZE: String(Math.max(1, Math.min(chunk.length, 50))),
      ORACLE_IMAGE_MAX_ROWS: String(chunk.length),
    });
    runNodeScript([
      'scripts/generate-oracle-homepage-card-images.js',
      '--apply',
      `--ids=${idList}`,
      '--limit=all',
      '--concurrency=4',
    ]);
  }
  return { ran: true, ids: ids.length, chunks: chunks.length };
}

async function refreshDerived(pool, apply) {
  if (!apply) {
    return {
      wouldRun: 'select public.refresh_marketplace_oracle_projections()',
      fallback: 'Runs component refresh functions individually if optional helpers are unavailable.',
    };
  }
  await pool.query('set statement_timeout = 0');
  await pool.query('set idle_in_transaction_session_timeout = 0');
  const helperCheck = await pool.query(`
    select
      to_regprocedure('public.refresh_marketplace_artist_card_counts()') is not null as has_artist_counts,
      to_regprocedure('public.refresh_marketplace_blueprint_price_summary()') is not null as has_price_summary,
      to_regprocedure('public.refresh_marketplace_hot_blueprints()') is not null as has_hot_blueprints
  `);
  const helpers = helperCheck.rows[0] || {};
  if (helpers.has_artist_counts && helpers.has_price_summary && helpers.has_hot_blueprints) {
    const result = await pool.query('select public.refresh_marketplace_oracle_projections() as result');
    return result.rows[0]?.result || {};
  }

  const steps = [
    ['marketplaceCards', 'refresh_marketplace_cards_from_blueprints', true],
    ['marketplaceCardVersions', 'refresh_marketplace_card_versions', true],
    ['searchCandidates', 'refresh_marketplace_search_candidates', true],
    ['marketplaceCardUrls', 'refresh_marketplace_card_urls', true],
    ['artistCardCounts', 'refresh_marketplace_artist_card_counts', helpers.has_artist_counts],
    ['tokenDimensions', 'refresh_marketplace_token_search_index', true],
    ['nameNgrams', 'refresh_marketplace_name_ngrams', true],
    ['priceSummaries', 'refresh_marketplace_blueprint_price_summary', helpers.has_price_summary],
    ['hotBlueprints', 'refresh_marketplace_hot_blueprints', helpers.has_hot_blueprints],
  ];
  const refreshed = { fallback: true, skipped: [], refreshedAt: new Date().toISOString() };
  for (const [key, functionName, available] of steps) {
    if (!available) {
      refreshed.skipped.push(functionName);
      continue;
    }
    const result = await pool.query(`select public.${functionName}() as count`);
    refreshed[key] = result.rows[0]?.count ?? null;
  }
  return refreshed;
}

function syncSupabase({ apply, languages, transport }) {
  const args = [
    'scripts/sync-card-name-index-to-supabase.js',
    '--full-refresh',
    `--languages=${languages}`,
    '--limit=all',
    `--transport=${transport}`,
  ];
  if (!apply) return { wouldRun: `node ${args.join(' ')}` };
  runNodeScript([args[0], '--apply', ...args.slice(1)]);
  return { ran: true, languages, transport };
}

async function run(options) {
  loadEnv();
  const pool = createMarketplacePool();
  try {
    if (!options.input) {
      return await runStreaming(pool, options);
    }
    const source = options.input
      ? { mode: 'input', records: readInputRecords(options.input, options), expansions: [] }
      : {
          mode: 'api',
          expansions: await resolveExpansions(options),
          records: [],
        };
    if (source.mode === 'api') {
      source.records = await fetchExpansionRecords(source.expansions, options);
    }
    const rows = uniqueRecords(source.records);
    const analysis = await analyzeRows(pool, rows, {
      apply: options.apply,
      batchSize: options.batchSize,
      collectImages: options.images,
    });
    const imageResult = options.images
      ? runImagePipeline(analysis.imageIds, { apply: options.apply })
      : { skipped: options.apply ? 'images flag not set' : 'dry-run' };
    const refreshResult = options.refresh
      ? await refreshDerived(pool, options.apply)
      : { skipped: 'refresh flag not set' };
    const supabaseResult = options.syncSupabase
      ? syncSupabase({
          apply: options.apply,
          languages: options.languages,
          transport: options.supabaseTransport,
        })
      : { skipped: 'sync flag not set' };

    return {
      mode: options.apply ? 'apply' : 'dry-run',
      source: {
        mode: source.mode,
        expansionIds: source.expansions.map((expansion) => expansion.id),
        expansionNames: source.expansions.map((expansion) => expansion.name),
        input: options.input || null,
        streaming: false,
      },
      counts: {
        fetched: rows.length,
        existingRaw: analysis.rawExisting.size,
        existingSearchCandidates: analysis.candidateExisting.size,
        missingImagesForNewOrUnprojectedRows: analysis.imageNeeded.size,
        missingRaw: analysis.missingRows.length,
        existingRawMissingSearchCandidate: analysis.existingRawMissingCandidate.length,
        inserted: analysis.inserted,
      },
      missingSamples: summarizeRows(analysis.missingRows),
      existingRawMissingSearchCandidateSamples: summarizeRows(analysis.existingRawMissingCandidate),
      imageResult,
      refreshResult,
      supabaseResult,
    };
  } finally {
    await pool.end().catch(() => {});
  }
}

async function runStreaming(pool, options) {
  const expansions = await resolveExpansions(options);
  const summary = createRunSummary({
    mode: options.apply ? 'apply' : 'dry-run',
    source: {
      mode: 'api',
      streaming: true,
      apiBase: CARDTRADER_API_BASE,
      note: 'CardTrader /blueprints/export returns full blueprint rows per expansion; no true ids-only endpoint is used.',
      expansionIds: expansions.map((expansion) => expansion.id),
      expansionNames: expansions.map((expansion) => expansion.name),
      input: null,
    },
  });

  for (const [index, expansion] of expansions.entries()) {
    if (summary.counts.fetched >= options.limit) break;
    const remaining = options.limit === Infinity ? Infinity : options.limit - summary.counts.fetched;
    const records = await fetchExpansionRecords([expansion], {
      sleepMs: 0,
      limit: remaining,
    });
    const rows = uniqueRecords(records);
    const analysis = await analyzeRows(pool, rows, {
      apply: options.apply,
      batchSize: options.batchSize,
      collectImages: options.images,
    });

    summary.counts.fetched += rows.length;
    summary.counts.existingRaw += analysis.rawExisting.size;
    summary.counts.existingSearchCandidates += analysis.candidateExisting.size;
    summary.counts.missingImagesForNewOrUnprojectedRows += analysis.imageNeeded.size;
    summary.counts.missingRaw += analysis.missingRows.length;
    summary.counts.existingRawMissingSearchCandidate += analysis.existingRawMissingCandidate.length;
    summary.counts.inserted += analysis.inserted;
    summary.imageIds.push(...analysis.imageIds);
    mergeSamples(summary.missingSamples, analysis.missingRows);
    mergeSamples(summary.existingRawMissingSearchCandidateSamples, analysis.existingRawMissingCandidate);
    if (
      analysis.missingRows.length > 0 ||
      analysis.existingRawMissingCandidate.length > 0 ||
      analysis.imageNeeded.size > 0 ||
      index === expansions.length - 1
    ) {
      summary.expansionProgress.push({
        expansion_id: expansion.id,
        expansion_name: expansion.name,
        fetched: rows.length,
        missingRaw: analysis.missingRows.length,
        existingRawMissingSearchCandidate: analysis.existingRawMissingCandidate.length,
        missingImagesForNewOrUnprojectedRows: analysis.imageNeeded.size,
        inserted: analysis.inserted,
      });
    }
    if (index < expansions.length - 1) await sleep(options.sleepMs);
  }

  summary.imageResult = options.images
    ? runImagePipeline(summary.imageIds, { apply: options.apply })
    : { skipped: options.apply ? 'images flag not set' : 'dry-run' };
  summary.refreshResult = options.refresh
    ? await refreshDerived(pool, options.apply)
    : { skipped: 'refresh flag not set' };
  summary.supabaseResult = options.syncSupabase
    ? syncSupabase({
        apply: options.apply,
        languages: options.languages,
        transport: options.supabaseTransport,
      })
    : { skipped: 'sync flag not set' };
  return summary;
}

if (require.main === module) {
  (async () => {
    try {
      const options = parseArgs(process.argv.slice(2));
      const result = await run(options);
      console.log(JSON.stringify(result, null, 2));
      if (!options.apply) {
        console.log('Dry run only; pass --apply after reviewing missing rows to mutate Oracle and optional derived targets.');
      }
    } catch (error) {
      console.error(error.message || error);
      process.exitCode = 1;
    }
  })();
}

module.exports = {
  insertMissingSql,
  insertValues,
  normalizeName,
  parseArgs,
  rowFromRecord,
  summarizeRows,
  tcgPlayerIds,
  uniqueRecords,
};
