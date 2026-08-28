#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const CARDTRADER_API_BASE = 'https://api.cardtrader.com/api/v2';
const DEFAULT_CONFIG_PATH = path.join(ROOT_DIR, 'config/cardtrader-marketplaces.json');
const DEFAULT_EXAMPLE_CONFIG_PATH = path.join(ROOT_DIR, 'config/cardtrader-marketplaces.example.json');
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
const DEFAULT_IMAGE_CHUNK_SIZE = 50;
const DEFAULT_HOMEPAGE_WIDTH = 240;

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

function parseIntegerCsv(value) {
  return parseCsv(value)
    .filter((item) => /^\d+$/.test(item))
    .map(Number);
}

function normalizeName(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function slugify(value) {
  return normalizeName(value).replace(/\s+/g, '-').slice(0, 120);
}

function envNameForGame(game) {
  return `${String(game || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')}_MARKETPLACE_DATABASE_URL`;
}

function schemaNameForGame(game) {
  const slug = slugify(game).replace(/-/g, '_');
  return `marketplace_${slug || 'cards'}`;
}

function parseArgs(argv) {
  const options = {
    apply: false,
    config: '',
    game: '',
    cardtraderGameId: null,
    cardtraderCategoryId: null,
    categoryName: '',
    databaseUrlEnv: '',
    schema: '',
    table: '',
    streamAll: false,
    expansionIds: [],
    limit: Infinity,
    batchSize: 500,
    concurrency: 6,
    imageConcurrency: 4,
    imageChunkSize: DEFAULT_IMAGE_CHUNK_SIZE,
    images: false,
    refresh: false,
    syncSearch: false,
    discoverOnly: false,
    ensureSchema: false,
    languages: 'en',
    supabaseTransport: 'rest',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--dry-run') {
      options.apply = false;
    } else if (arg === '--stream-all') {
      options.streamAll = true;
    } else if (arg === '--images') {
      options.images = true;
    } else if (arg === '--no-images') {
      options.images = false;
    } else if (arg === '--refresh') {
      options.refresh = true;
    } else if (arg === '--sync-search' || arg === '--sync-supabase') {
      options.syncSearch = true;
    } else if (arg === '--discover-only') {
      options.discoverOnly = true;
    } else if (arg === '--ensure-schema') {
      options.ensureSchema = true;
    } else if (arg.startsWith('--config=')) {
      options.config = arg.slice('--config='.length).trim();
    } else if (arg.startsWith('--game=')) {
      options.game = arg.slice('--game='.length).trim();
    } else if (arg.startsWith('--cardtrader-game-id=')) {
      options.cardtraderGameId = Number(arg.slice('--cardtrader-game-id='.length));
    } else if (arg.startsWith('--cardtrader-category-id=')) {
      options.cardtraderCategoryId = Number(arg.slice('--cardtrader-category-id='.length));
    } else if (arg.startsWith('--category-name=')) {
      options.categoryName = arg.slice('--category-name='.length).trim();
    } else if (arg.startsWith('--database-url-env=')) {
      options.databaseUrlEnv = arg.slice('--database-url-env='.length).trim();
    } else if (arg.startsWith('--schema=')) {
      options.schema = arg.slice('--schema='.length).trim();
    } else if (arg.startsWith('--table=')) {
      options.table = arg.slice('--table='.length).trim();
    } else if (arg.startsWith('--expansion-ids=')) {
      options.expansionIds = parseIntegerCsv(arg.slice('--expansion-ids='.length));
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? Infinity : Number(raw);
    } else if (arg.startsWith('--batch-size=')) {
      options.batchSize = Number(arg.slice('--batch-size='.length));
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Number(arg.slice('--concurrency='.length));
    } else if (arg.startsWith('--image-concurrency=')) {
      options.imageConcurrency = Number(arg.slice('--image-concurrency='.length));
    } else if (arg.startsWith('--image-chunk-size=')) {
      options.imageChunkSize = Number(arg.slice('--image-chunk-size='.length));
    } else if (arg.startsWith('--languages=')) {
      options.languages = arg.slice('--languages='.length).trim() || 'en';
    } else if (arg.startsWith('--supabase-transport=')) {
      options.supabaseTransport = arg.slice('--supabase-transport='.length).trim() || 'rest';
    }
  }
  if (!options.game) {
    throw new Error('--game is required.');
  }
  if (options.cardtraderGameId != null && !Number.isSafeInteger(options.cardtraderGameId)) {
    throw new Error('--cardtrader-game-id must be an integer.');
  }
  if (options.cardtraderCategoryId != null && !Number.isSafeInteger(options.cardtraderCategoryId)) {
    throw new Error('--cardtrader-category-id must be an integer.');
  }
  if (!Number.isFinite(options.limit) && options.limit !== Infinity) {
    throw new Error('--limit must be a number or all.');
  }
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 5000) {
    throw new Error('--batch-size must be between 1 and 5000.');
  }
  if (!Number.isSafeInteger(options.concurrency) || options.concurrency < 1 || options.concurrency > 50) {
    throw new Error('--concurrency must be between 1 and 50.');
  }
  if (!Number.isSafeInteger(options.imageConcurrency) || options.imageConcurrency < 1 || options.imageConcurrency > 50) {
    throw new Error('--image-concurrency must be between 1 and 50.');
  }
  if (!Number.isSafeInteger(options.imageChunkSize) || options.imageChunkSize < 1 || options.imageChunkSize > 500) {
    throw new Error('--image-chunk-size must be between 1 and 500.');
  }
  if (!options.discoverOnly && !options.streamAll && options.expansionIds.length === 0) {
    throw new Error('Use --stream-all, --expansion-ids, or --discover-only for a bounded multi-game import.');
  }
  return options;
}

function readJsonIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function gameConfigKey(game) {
  return slugify(game).replace(/-/g, '_');
}

function loadConfig(options) {
  const explicit = options.config ? path.resolve(ROOT_DIR, options.config) : '';
  if (explicit) {
    return readJsonIfExists(explicit) || {};
  }
  return readJsonIfExists(DEFAULT_CONFIG_PATH) || {};
}

function resolveConfiguredTarget(options, config = {}) {
  const key = gameConfigKey(options.game);
  const configGames = config.games || {};
  const entry = configGames[key] || configGames[options.game] || {};
  const gameSlug = slugify(entry.slug || options.game);
  const isPokemon = ['pokemon', 'pokemon-tcg', 'pokémon'].includes(gameSlug);
  return {
    key,
    game: options.game,
    displayName: entry.displayName || entry.display_name || options.game,
    slug: gameSlug,
    cardtraderGameId: options.cardtraderGameId ?? entry.cardtraderGameId ?? entry.cardtrader_game_id ?? (isPokemon ? 5 : null),
    cardtraderCategoryId: options.cardtraderCategoryId ?? entry.cardtraderCategoryId ?? entry.cardtrader_category_id ?? null,
    categoryName: options.categoryName || entry.categoryName || entry.category_name || '',
    databaseUrlEnv: options.databaseUrlEnv || entry.databaseUrlEnv || entry.database_url_env || (isPokemon ? 'MARKETPLACE_DATABASE_URL' : envNameForGame(options.game)),
    schema: options.schema || entry.schema || (isPokemon ? 'public' : schemaNameForGame(options.game)),
    table: options.table || entry.table || (isPokemon ? 'cardtrader_pokemon_blueprints' : 'cardtrader_blueprints'),
    cdnKeyPrefix: entry.cdnKeyPrefix ?? entry.cdn_key_prefix ?? (isPokemon ? '' : `${gameSlug}/`),
    bucketEnv: entry.bucketEnv || entry.bucket_env || 'POKOIN_CARD_IMAGES_BUCKET',
    cdnBaseEnv: entry.cdnBaseEnv || entry.cdn_base_env || 'POKOIN_CARD_CDN_BASE_URL',
    refreshSql: entry.refreshSql || entry.refresh_sql || '',
    syncCommand: entry.syncCommand || entry.sync_command || '',
    notes: entry.notes || '',
  };
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function quoteIdent(value) {
  const text = String(value || '');
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(text)) {
    throw new Error(`Unsafe SQL identifier: ${text}`);
  }
  return `"${text.replaceAll('"', '""')}"`;
}

function qualifiedTable(target) {
  return `${quoteIdent(target.schema)}.${quoteIdent(target.table)}`;
}

function createTargetPool(target, options) {
  const connectionString = process.env[target.databaseUrlEnv];
  if (!connectionString) return null;
  return new Pool({
    connectionString,
    max: Math.min(Math.max(2, options.concurrency), 20),
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env[`${target.databaseUrlEnv}_SSL_VERIFY`] === '1' },
  });
}

async function cardtraderGet(apiPath, params = {}, token = process.env.CARDTRADER_AUTH_TOKEN) {
  if (!token) throw new Error('CARDTRADER_AUTH_TOKEN is required for CardTrader API discovery/import.');
  const url = new URL(`${CARDTRADER_API_BASE}${apiPath}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      'User-Agent': 'pokoin-cardtrader-multigame-import/1.0',
    },
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) {
    throw new Error(`CardTrader ${apiPath} failed: HTTP ${response.status}: ${await response.text()}`);
  }
  return asList(await response.json());
}

function asList(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.array)) return payload.array;
  throw new Error(`Unexpected CardTrader response shape: ${typeof payload}`);
}

function matchCardTraderGame(games, target) {
  if (target.cardtraderGameId != null) {
    const byId = games.find((game) => Number(game.id) === Number(target.cardtraderGameId));
    if (byId) return byId;
  }
  const needle = normalizeName(target.displayName || target.game || target.slug);
  const slugNeedle = normalizeName(target.slug);
  const match = games.find((game) => {
    const haystack = normalizeName(`${game.name || ''} ${game.display_name || ''}`);
    return haystack === needle ||
      haystack === slugNeedle ||
      haystack.includes(needle) ||
      haystack.includes(slugNeedle);
  });
  if (!match) {
    throw new Error(`Could not find CardTrader game for "${target.displayName}". Use --cardtrader-game-id.`);
  }
  return match;
}

function matchCategory(categories, target) {
  if (target.cardtraderCategoryId != null) {
    const byId = categories.find((category) => Number(category.id) === Number(target.cardtraderCategoryId));
    if (!byId) throw new Error(`Could not find CardTrader category id ${target.cardtraderCategoryId}.`);
    return byId;
  }
  if (!target.categoryName) return null;
  const needle = normalizeName(target.categoryName);
  const match = categories.find((category) => {
    const haystack = normalizeName(`${category.name || ''} ${category.display_name || ''}`);
    return haystack === needle || haystack.includes(needle);
  });
  if (!match) throw new Error(`Could not find CardTrader category "${target.categoryName}".`);
  return match;
}

async function discoverCardTraderTarget(target, api = { get: cardtraderGet }) {
  const games = await api.get('/games');
  const game = matchCardTraderGame(games, target);
  const [categories, allExpansions] = await Promise.all([
    api.get('/categories', { game_id: game.id }).catch(() => []),
    api.get('/expansions'),
  ]);
  const gameCategories = categories.filter((category) => Number(category.game_id) === Number(game.id));
  const selectedCategory = matchCategory(gameCategories, {
    ...target,
    cardtraderGameId: Number(game.id),
  });
  const expansions = allExpansions
    .filter((expansion) => Number(expansion.game_id) === Number(game.id))
    .sort((a, b) => Number(a.id) - Number(b.id));
  return {
    game,
    categories: gameCategories,
    selectedCategory,
    expansions,
  };
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
    image_url: cleanBlueprintImageUrl(blueprint.image_url),
    card_market_ids: blueprint.card_market_ids ?? null,
    tcg_player_ids: tcgPlayerIds(blueprint),
    editable_properties: blueprint.editable_properties || [],
    blueprint,
    expansion: record.expansion || null,
  };
}

function tcgPlayerIds(blueprint) {
  if (Array.isArray(blueprint.tcg_player_ids)) return blueprint.tcg_player_ids;
  if (blueprint.tcg_player_id == null || blueprint.tcg_player_id === '') return null;
  return [blueprint.tcg_player_id];
}

function cleanBlueprintImageUrl(value) {
  const rawUrl = String(value || '').trim();
  if (!rawUrl || rawUrl.includes('/fallbacks/card_uploader/')) {
    return null;
  }
  return rawUrl;
}

function uniqueRows(records) {
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

function selectExpansions(discovery, options) {
  if (options.streamAll || options.discoverOnly) {
    return discovery.expansions;
  }
  const ids = new Set(options.expansionIds.map(Number));
  return discovery.expansions.filter((expansion) => ids.has(Number(expansion.id)));
}

async function fetchExpansionRecords(expansion, discovery, api = { get: cardtraderGet }) {
  const blueprints = await api.get('/blueprints/export', { expansion_id: expansion.id });
  return blueprints
    .filter((blueprint) => {
      if (!discovery.selectedCategory) return true;
      return Number(blueprint.category_id) === Number(discovery.selectedCategory.id);
    })
    .map((blueprint) => ({
      blueprint,
      expansion,
      game: discovery.game,
    }));
}

async function existingIdSet(pool, ids, target) {
  if (!pool || ids.length === 0) return null;
  const result = await pool.query(
    `select id::text as id from ${qualifiedTable(target)} where id = any($1::bigint[])`,
    [ids],
  );
  return new Set(result.rows.map((row) => row.id));
}

function insertMissingSql(rowCount, target) {
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
  const columns = BLUEPRINT_COLUMNS.map(quoteIdent).join(', ');
  return `
    insert into ${qualifiedTable(target)} (${columns})
    values ${placeholders.join(', ')}
    on conflict (id) do nothing
    returning id
  `;
}

function insertValues(rows) {
  return rows.flatMap((row) =>
    BLUEPRINT_COLUMNS.map((column) =>
      JSON_COLUMNS.has(column) ? JSON.stringify(row[column] ?? null) : row[column] ?? null,
    ),
  );
}

async function insertMissingRows(pool, rows, target, batchSize) {
  const insertedIds = new Set();
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    const result = await pool.query(insertMissingSql(batch.length, target), insertValues(batch));
    for (const row of result.rows) {
      insertedIds.add(String(row.id));
    }
  }
  return rows.filter((row) => insertedIds.has(String(row.id)));
}

function createRawTableSql(target) {
  return `
create schema if not exists ${quoteIdent(target.schema)};

create table if not exists ${qualifiedTable(target)} (
  id bigint primary key,
  name text not null,
  version text,
  game_id integer not null,
  category_id integer,
  expansion_id integer,
  image_url text,
  cardtrader_image_url text,
  cdn_image_url text,
  cdn_object_key text,
  preview_image_url text,
  preview_object_key text,
  homepage_image_url text,
  homepage_object_key text,
  card_market_ids jsonb,
  tcg_player_ids jsonb,
  editable_properties jsonb not null default '[]'::jsonb,
  blueprint jsonb not null,
  expansion jsonb,
  imported_at timestamptz not null default now()
);

create index if not exists ${quoteIdent(`${target.schema}_${target.table}_expansion_id_idx`)}
  on ${qualifiedTable(target)} (expansion_id);

create index if not exists ${quoteIdent(`${target.schema}_${target.table}_category_id_idx`)}
  on ${qualifiedTable(target)} (category_id);
`.trim();
}

async function ensureRawSchema(pool, target) {
  await pool.query(createRawTableSql(target));
}

function summarizeRows(rows) {
  return rows.slice(0, 25).map((row) => ({
    id: row.id,
    name: row.name,
    version: row.version,
    game_id: row.game_id,
    category_id: row.category_id,
    expansion_id: row.expansion_id,
    expansion_name: row.expansion?.name || '',
    image: Boolean(row.blueprint?.image?.url || row.blueprint?.image_url || row.image_url),
  }));
}

function chunkArray(values, size) {
  const chunks = [];
  for (let offset = 0; offset < values.length; offset += size) {
    chunks.push(values.slice(offset, offset + size));
  }
  return chunks;
}

function planImageJobs(ids, target, options) {
  if (!options.images) return { skipped: 'images flag not set' };
  if (ids.length === 0) return { skipped: 'no newly imported ids' };
  const chunks = chunkArray(ids, options.imageChunkSize || DEFAULT_IMAGE_CHUNK_SIZE);
  return {
    derivatives: ['full', 'preview', 'homepage'],
    limitedTo: 'newly imported blueprint ids',
    target: {
      schema: target.schema,
      table: target.table,
      cdnKeyPrefix: target.cdnKeyPrefix,
    },
    chunks: chunks.map((chunk) => ({ ids: chunk })),
  };
}

function normalizeCardTraderUrl(rawValue, { allowPreview }) {
  const rawUrl = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (!rawUrl || rawUrl.includes('/fallbacks/card_uploader/')) return null;
  if (!allowPreview && rawUrl.includes('/preview_')) return null;
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) return rawUrl;
  if (rawUrl.startsWith('/')) return `https://cardtrader.com${rawUrl}`;
  return `https://cardtrader.com/${rawUrl}`;
}

function fullImageUrls(row) {
  const image = row.blueprint?.image;
  return [...new Set([
    typeof image?.url === 'string' ? image.url : null,
    typeof image?.show?.url === 'string' ? image.show.url : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof row.image_url === 'string' && row.image_url.includes('cardtrader.com') ? row.image_url : null,
  ].map((candidate) => normalizeCardTraderUrl(candidate, { allowPreview: false })).filter(Boolean))];
}

function previewImageUrls(row) {
  const image = row.blueprint?.image;
  return [...new Set([
    typeof image?.preview?.url === 'string' ? image.preview.url : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof image?.show?.url === 'string' ? image.show.url : null,
    typeof image?.url === 'string' ? image.url : null,
  ].map((candidate) => normalizeCardTraderUrl(candidate, { allowPreview: true })).filter(Boolean))];
}

function extensionFromUrl(url) {
  const pathname = new URL(url).pathname;
  const match = pathname.match(/\.([a-zA-Z0-9]+)$/);
  const ext = match ? match[1].toLowerCase() : 'jpg';
  return ext === 'jpeg' ? 'jpg' : ext;
}

function extensionFromContentType(contentType) {
  const normalized = String(contentType || '').toLowerCase();
  if (normalized.includes('image/webp')) return 'webp';
  if (normalized.includes('image/png')) return 'png';
  if (normalized.includes('image/gif')) return 'gif';
  if (normalized.includes('image/jpeg') || normalized.includes('image/jpg')) return 'jpg';
  return null;
}

function imageFormatFromBytes(body) {
  if (!Buffer.isBuffer(body) || body.length < 12) return null;
  if (body[0] === 0xff && body[1] === 0xd8 && body[2] === 0xff) return 'jpg';
  if (body.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (body.slice(0, 6).toString('ascii') === 'GIF87a' || body.slice(0, 6).toString('ascii') === 'GIF89a') return 'gif';
  if (body.slice(0, 4).toString('ascii') === 'RIFF' && body.slice(8, 12).toString('ascii') === 'WEBP') return 'webp';
  return null;
}

function contentTypeForExtension(ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

async function downloadImage(sourceUrl, minBytes) {
  const response = await fetch(sourceUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Pokoin multigame image importer)',
      Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    },
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) throw new Error(`download failed ${response.status}: ${sourceUrl}`);
  const body = Buffer.from(await response.arrayBuffer());
  if (body.length < minBytes) throw new Error(`download too small (${body.length} bytes): ${sourceUrl}`);
  return { body, contentType: response.headers.get('content-type') || '' };
}

async function firstImageDownload(candidates, minBytes) {
  const errors = [];
  for (const sourceUrl of candidates) {
    try {
      return { sourceUrl, ...(await downloadImage(sourceUrl, minBytes)) };
    } catch (error) {
      errors.push(`${sourceUrl}: ${error.message}`);
    }
  }
  throw new Error(errors.join(' | ') || 'no image candidates');
}

function keyPrefix(target) {
  const prefix = String(target.cdnKeyPrefix || '').replace(/^\/+/, '');
  return prefix && !prefix.endsWith('/') ? `${prefix}/` : prefix;
}

function objectKeysForRow(row, target, ext) {
  const slug = slugify(row.name) || `card-${row.id}`;
  const prefix = keyPrefix(target);
  const basename = `${row.id}_${slug}`;
  return {
    fullKey: `${prefix}${basename}.${ext}`,
    previewKey: `${prefix}previews/${basename}.webp`,
    homepageKey: `${prefix}${basename}_homepage.webp`,
  };
}

async function updateImageColumns(pool, target, row, updates) {
  await pool.query(
    `
      update ${qualifiedTable(target)}
      set
        image_url = $1,
        cardtrader_image_url = $2,
        cdn_image_url = $1,
        cdn_object_key = $3,
        preview_image_url = $4,
        preview_object_key = $5,
        homepage_image_url = $6,
        homepage_object_key = $7
      where id = $8
    `,
    [
      updates.fullUrl,
      updates.sourceUrl,
      updates.fullKey,
      updates.previewUrl,
      updates.previewKey,
      updates.homepageUrl,
      updates.homepageKey,
      row.id,
    ],
  );
}

async function runWorkers(items, concurrency, worker) {
  let index = 0;
  const results = [];
  async function runOne() {
    while (index < items.length) {
      const itemIndex = index;
      index += 1;
      results[itemIndex] = await worker(items[itemIndex], itemIndex);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length || 1) }, () => runOne()));
  return results;
}

async function runGenericImagePipeline(pool, rows, target, options) {
  const imagePlan = planImageJobs(rows.map((row) => row.id), target, options);
  if (!options.images || !options.apply || rows.length === 0) return imagePlan;

  const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
  const sharp = require('sharp');
  const env = process.env;
  requireEnv('CLOUDFLARE_ACCOUNT_ID');
  requireEnv('R2_ACCESS_KEY_ID');
  requireEnv('R2_SECRET_ACCESS_KEY');
  const bucket = env[target.bucketEnv] || env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env[target.cdnBaseEnv] || env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });
  const summary = { attempted: 0, imported: 0, failed: 0, samples: [] };
  await runWorkers(rows, options.imageConcurrency, async (row) => {
    summary.attempted += 1;
    try {
      const source = await firstImageDownload(fullImageUrls(row), 1024);
      const ext = imageFormatFromBytes(source.body) ||
        extensionFromContentType(source.contentType) ||
        extensionFromUrl(source.sourceUrl);
      const keys = objectKeysForRow(row, target, ext);
      const previewSource = previewImageUrls(row)[0] === source.sourceUrl
        ? source
        : await firstImageDownload(previewImageUrls(row), 256).catch(() => source);
      const previewBody = await sharp(previewSource.body)
        .rotate()
        .resize({ width: 96, height: 134, fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 72 })
        .toBuffer();
      const homepageBody = await sharp(source.body)
        .rotate()
        .resize({ width: DEFAULT_HOMEPAGE_WIDTH, withoutEnlargement: true })
        .webp({ quality: 82 })
        .toBuffer();
      await Promise.all([
        client.send(new PutObjectCommand({
          Bucket: bucket,
          Key: keys.fullKey,
          Body: source.body,
          ContentType: contentTypeForExtension(ext),
          CacheControl: 'public, max-age=31536000, immutable',
        })),
        client.send(new PutObjectCommand({
          Bucket: bucket,
          Key: keys.previewKey,
          Body: previewBody,
          ContentType: 'image/webp',
          CacheControl: 'public, max-age=31536000, immutable',
        })),
        client.send(new PutObjectCommand({
          Bucket: bucket,
          Key: keys.homepageKey,
          Body: homepageBody,
          ContentType: 'image/webp',
          CacheControl: 'public, max-age=31536000, immutable',
        })),
      ]);
      await updateImageColumns(pool, target, row, {
        sourceUrl: source.sourceUrl,
        fullUrl: `${cdnBase}/${keys.fullKey}`,
        fullKey: keys.fullKey,
        previewUrl: `${cdnBase}/${keys.previewKey}`,
        previewKey: keys.previewKey,
        homepageUrl: `${cdnBase}/${keys.homepageKey}`,
        homepageKey: keys.homepageKey,
      });
      summary.imported += 1;
      if (summary.samples.length < 10) summary.samples.push({ id: row.id, fullKey: keys.fullKey });
    } catch (error) {
      summary.failed += 1;
      if (summary.samples.length < 10) summary.samples.push({ id: row.id, error: error.message });
    }
  });
  return { ...imagePlan, summary };
}

async function refreshTarget(pool, target, options) {
  if (!options.refresh) return { skipped: 'refresh flag not set' };
  if (!target.refreshSql) return { blocked: 'target refreshSql is not configured for this game' };
  if (!options.apply) return { wouldRun: target.refreshSql };
  const result = await pool.query(target.refreshSql);
  return { ran: true, rowCount: result.rowCount };
}

function syncSearchTarget(target, options) {
  if (!options.syncSearch) return { skipped: 'sync-search flag not set' };
  if (!target.syncCommand) return { blocked: 'target syncCommand is not configured for this game' };
  if (!options.apply) return { wouldRun: target.syncCommand };
  const result = spawnSync(target.syncCommand, {
    cwd: ROOT_DIR,
    env: process.env,
    shell: true,
    stdio: 'inherit',
  });
  if (result.status !== 0) throw new Error(`${target.syncCommand} failed with exit code ${result.status}`);
  return { ran: true };
}

function createSummary(options, target, discovery) {
  return {
    mode: options.apply ? 'apply' : 'dry-run',
    target: {
      game: target.game,
      displayName: target.displayName,
      schema: target.schema,
      table: target.table,
      databaseUrlEnv: target.databaseUrlEnv,
      cdnKeyPrefix: target.cdnKeyPrefix,
    },
    cardtrader: {
      apiBase: CARDTRADER_API_BASE,
      game: discovery.game,
      selectedCategory: discovery.selectedCategory,
      categoryCount: discovery.categories.length,
      expansionCount: discovery.expansions.length,
    },
    counts: {
      fetched: 0,
      existingRaw: 0,
      missingRaw: 0,
      inserted: 0,
      failedExpansions: 0,
    },
    blockers: [],
    missingSamples: [],
    expansionProgress: [],
  };
}

function addSamples(summary, rows) {
  for (const sample of summarizeRows(rows)) {
    if (summary.missingSamples.length >= 25) break;
    summary.missingSamples.push(sample);
  }
}

async function processExpansion({ pool, target, options, discovery, expansion, api, rowLimit = Infinity }) {
  const records = await fetchExpansionRecords(expansion, discovery, api);
  const limitedRecords = rowLimit === Infinity ? records : records.slice(0, Math.max(0, rowLimit));
  const rows = uniqueRows(limitedRecords);
  const existing = await existingIdSet(pool, rows.map((row) => row.id), target);
  const missingRows = existing
    ? rows.filter((row) => !existing.has(String(row.id)))
    : rows;
  const inserted = options.apply && pool
    ? await insertMissingRows(pool, missingRows, target, options.batchSize)
    : [];
  return {
    expansion,
    rows,
    existingCount: existing ? existing.size : 0,
    missingRows,
    insertedRows: inserted,
    inserted: inserted.length,
    dbCompared: Boolean(existing),
  };
}

async function run(options, dependencies = {}) {
  loadEnv();
  const config = dependencies.config || loadConfig(options);
  const target = dependencies.target || resolveConfiguredTarget(options, config);
  const api = dependencies.api || { get: cardtraderGet };
  const discovery = await discoverCardTraderTarget(target, api);
  const selectedExpansions = selectExpansions(discovery, options);
  const summary = createSummary(options, target, discovery);
  summary.cardtrader.selectedExpansionCount = selectedExpansions.length;
  summary.cardtrader.selectedExpansionIds = selectedExpansions.slice(0, 100).map((expansion) => expansion.id);
  if (options.discoverOnly) {
    summary.discovery = {
      gamesConfigPath: options.config || (fs.existsSync(DEFAULT_CONFIG_PATH) ? DEFAULT_CONFIG_PATH : DEFAULT_EXAMPLE_CONFIG_PATH),
      categories: discovery.categories.map((category) => ({
        id: category.id,
        name: category.name || category.display_name || '',
        game_id: category.game_id,
      })),
      expansionSamples: selectedExpansions.slice(0, 25).map((expansion) => ({
        id: expansion.id,
        name: expansion.name,
        game_id: expansion.game_id,
      })),
    };
    return summary;
  }

  const pool = dependencies.pool || createTargetPool(target, options);
  if (!pool) {
    summary.blockers.push(`${target.databaseUrlEnv} is not configured; cannot compare or upsert target ${target.schema}.${target.table}.`);
    summary.schemaPlan = createRawTableSql(target);
    summary.imageResult = planImageJobs([], target, options);
    summary.refreshResult = options.refresh
      ? { blocked: 'database target is not configured' }
      : { skipped: 'refresh flag not set' };
    summary.syncSearchResult = syncSearchTarget(target, { ...options, apply: false });
    return summary;
  }

  const imageRows = [];
  try {
    if (options.apply && options.ensureSchema) {
      await ensureRawSchema(pool, target);
    } else if (!options.apply) {
      summary.schemaPlan = createRawTableSql(target);
    }

    let processedExpansionCount = 0;
    let fetchedRows = 0;
    const importConcurrency = options.limit === Infinity ? options.concurrency : 1;
    await runWorkers(selectedExpansions, importConcurrency, async (expansion) => {
      if (options.limit !== Infinity && fetchedRows >= options.limit) return;
      const rowLimit = options.limit === Infinity ? Infinity : options.limit - fetchedRows;
      try {
        const result = await processExpansion({
          pool,
          target,
          options,
          discovery,
          expansion,
          api,
          rowLimit,
        });
        const acceptedRows = options.limit === Infinity
          ? result.rows
          : result.rows.slice(0, Math.max(0, options.limit - fetchedRows));
        fetchedRows += acceptedRows.length;
        summary.counts.fetched += acceptedRows.length;
        summary.counts.existingRaw += result.existingCount;
        summary.counts.missingRaw += result.missingRows.length;
        summary.counts.inserted += result.inserted;
        imageRows.push(...(options.apply ? result.insertedRows : result.missingRows));
        addSamples(summary, result.missingRows);
        processedExpansionCount += 1;
        if (result.missingRows.length > 0 || processedExpansionCount === selectedExpansions.length) {
          summary.expansionProgress.push({
            expansion_id: expansion.id,
            expansion_name: expansion.name,
            fetched: result.rows.length,
            existingRaw: result.existingCount,
            missingRaw: result.missingRows.length,
            inserted: result.inserted,
          });
        }
      } catch (error) {
        summary.counts.failedExpansions += 1;
        summary.expansionProgress.push({
          expansion_id: expansion.id,
          expansion_name: expansion.name,
          error: error.message,
        });
      }
    });

    summary.imageResult = await runGenericImagePipeline(pool, imageRows, target, options);
    summary.refreshResult = await refreshTarget(pool, target, options);
    summary.syncSearchResult = syncSearchTarget(target, options);
    return summary;
  } finally {
    if (!dependencies.pool) {
      await pool.end().catch(() => {});
    }
  }
}

if (require.main === module) {
  (async () => {
    try {
      const options = parseArgs(process.argv.slice(2));
      const result = await run(options);
      console.log(JSON.stringify(result, null, 2));
      if (!options.apply) {
        console.log('Dry run only; pass --apply with an explicit isolated target DB/schema after reviewing the plan.');
      }
    } catch (error) {
      console.error(error.message || error);
      process.exitCode = 1;
    }
  })();
}

module.exports = {
  BLUEPRINT_COLUMNS,
  createRawTableSql,
  discoverCardTraderTarget,
  envNameForGame,
  existingIdSet,
  insertMissingSql,
  insertValues,
  matchCardTraderGame,
  normalizeName,
  objectKeysForRow,
  parseArgs,
  planImageJobs,
  quoteIdent,
  resolveConfiguredTarget,
  rowFromRecord,
  run,
  schemaNameForGame,
  summarizeRows,
  tcgPlayerIds,
  uniqueRows,
};
