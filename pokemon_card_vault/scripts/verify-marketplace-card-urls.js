#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_CHUNK_SIZE = 100;
const DEFAULT_CONCURRENCY = 32;
const DEFAULT_POOL_MAX = 16;
const DEFAULT_SAMPLE_LIMIT = 20;

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

function loadEnvFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function loadLocalEnv() {
  loadEnvFile(path.join(ROOT_DIR, '.env.local'));
  loadEnvFile(DEFAULT_ORACLE_ENV);
}

function parsePositiveInt(value, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function parseNonNegativeInt(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(Math.trunc(number), 0);
}

function parseLimit(value) {
  const raw = String(value ?? '').trim().toLowerCase();
  if (!raw) return null;
  if (raw === 'all' || raw === 'none') return null;
  const limit = Number(raw);
  if (!Number.isFinite(limit) || limit < 1) {
    throw new Error('--limit must be a positive number or all.');
  }
  return Math.trunc(limit);
}

function parseChunks(value) {
  const raw = String(value ?? 'all').trim().toLowerCase();
  if (raw === 'all' || raw === 'none') return null;
  const chunks = Number(raw);
  if (!Number.isFinite(chunks) || chunks < 1) {
    throw new Error('--chunks must be a positive number or all.');
  }
  return Math.trunc(chunks);
}

function optionValue(argv, index) {
  const token = argv[index];
  const equals = token.indexOf('=');
  if (equals >= 0) return { value: token.slice(equals + 1), nextIndex: index };
  const next = argv[index + 1];
  if (next && !next.startsWith('--')) return { value: next, nextIndex: index + 1 };
  return { value: true, nextIndex: index };
}

function parseArgs(argv) {
  const options = {
    chunkSize: DEFAULT_CHUNK_SIZE,
    chunks: null,
    start: 0,
    limit: null,
    concurrency: DEFAULT_CONCURRENCY,
    poolMax: DEFAULT_POOL_MAX,
    scope: 'cards',
    sampleLimit: DEFAULT_SAMPLE_LIMIT,
    progressEvery: 50,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2).split('=', 1)[0];
    const parsed = optionValue(argv, index);
    index = parsed.nextIndex;
    const value = parsed.value;

    if (key === 'chunk-size') {
      options.chunkSize = parsePositiveInt(value, DEFAULT_CHUNK_SIZE, { min: 1, max: 5000 });
    } else if (key === 'chunks') {
      options.chunks = parseChunks(value);
    } else if (key === 'start') {
      options.start = parseNonNegativeInt(value, 0);
    } else if (key === 'limit') {
      options.limit = parseLimit(value);
    } else if (key === 'concurrency') {
      options.concurrency = parsePositiveInt(value, DEFAULT_CONCURRENCY, { min: 1, max: 1000 });
    } else if (key === 'pool-max') {
      options.poolMax = parsePositiveInt(value, DEFAULT_POOL_MAX, { min: 1, max: 100 });
    } else if (key === 'scope') {
      options.scope = String(value || '').trim().toLowerCase() || 'cards';
    } else if (key === 'sample-limit') {
      options.sampleLimit = parsePositiveInt(value, DEFAULT_SAMPLE_LIMIT, { min: 1, max: 200 });
    } else if (key === 'progress-every') {
      options.progressEvery = parsePositiveInt(value, 50, { min: 1, max: 10000 });
    } else if (key === 'help') {
      options.help = true;
    }
  }

  if (!['cards', 'visible-cards', 'all'].includes(options.scope)) {
    throw new Error('--scope must be cards, visible-cards, or all.');
  }
  return options;
}

function usage() {
  return `
Usage:
  node scripts/verify-marketplace-card-urls.js [options]

Options:
  --chunk-size=100       Logical cards per chunk.
  --chunks=all|400      Number of chunks to process. Defaults to all eligible rows.
  --start=0             Row offset in card_id order.
  --limit=all|40000     Optional row cap. Overrides --chunks when smaller.
  --concurrency=100     Parallel logical chunk workers.
  --pool-max=16         Maximum open Postgres clients in the single pg pool.
  --scope=cards         cards, visible-cards, or all. Defaults to cards.
  --sample-limit=20     Representative examples retained per failure class.
  --progress-every=50   Progress line interval in completed chunks.
`.trim();
}

function marketplaceDatabaseConfig(options) {
  const directUrl = process.env.MARKETPLACE_DATABASE_URL ||
    process.env.MARKETPLACE_PEER4_DATABASE_URL ||
    '';
  const sslVerify = process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1';
  if (directUrl) {
    const connectionString = sslVerify
      ? directUrl
      : directUrl.replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
          prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '',
        ).replace(/[?&]$/, '');
    return {
      connectionString,
      max: options.poolMax,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 10_000,
      ssl: { rejectUnauthorized: sslVerify },
      application_name: 'marketplace-card-url-verifier',
    };
  }

  for (const key of [
    'MARKETPLACE_DB_PUBLIC_HOST',
    'MARKETPLACE_DB_USER',
    'MARKETPLACE_DB_PASSWORD',
    'MARKETPLACE_DB_NAME',
  ]) {
    if (!process.env[key]) {
      throw new Error('MARKETPLACE_DATABASE_URL or peer4 MARKETPLACE_DB_* env is required.');
    }
  }
  return {
    host: process.env.MARKETPLACE_DB_PUBLIC_HOST,
    port: Number(process.env.MARKETPLACE_DB_PORT || 5432),
    database: process.env.MARKETPLACE_DB_NAME,
    user: process.env.MARKETPLACE_DB_USER,
    password: process.env.MARKETPLACE_DB_PASSWORD,
    max: options.poolMax,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: sslVerify },
    application_name: 'marketplace-card-url-verifier',
  };
}

function scopeWhere(scope) {
  const clauses = [];
  if (scope === 'cards' || scope === 'visible-cards') {
    clauses.push("coalesce(c.item_kind, 'single') = 'single'");
    clauses.push("coalesce(c.product_type, 'card') = 'card'");
  }
  if (scope === 'visible-cards') {
    clauses.push("coalesce(c.preview_image_url, c.cdn_image_url, c.image_url, '') <> ''");
  }
  return clauses.length > 0 ? `where ${clauses.join(' and ')}` : '';
}

function cleanText(value) {
  return String(value || '').trim();
}

function slugPart(value) {
  return cleanText(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function cardDetailSlug(row) {
  return [
    row.rarity ? row.rarity : 'Card',
    row.name,
    collectorNumberForUrl(row),
    row.set_name,
  ].map(slugPart).filter(Boolean).join('-');
}

function collectorNumberForUrl(row) {
  const image = cleanText(row.image_url || row.cdn_image_url || row.homepage_image_url || row.preview_image_url);
  const match = image.match(/([0-9]{1,4}[A-Za-z]?[-/][0-9]{1,4})/);
  if (match) return match[1].replace('-', '/');
  return cleanText(row.version) || cleanText(row.collector_number);
}

function doubledBlueprintId(row) {
  const id = Number(row.blueprint_id);
  if (!Number.isSafeInteger(id) || id <= 0) return '';
  return String(id * 2);
}

function canonicalPath(row, slug = cardDetailSlug(row), language = 'en') {
  const doubledId = doubledBlueprintId(row);
  if (!doubledId || !slug) return '';
  return `/marketplace/${slugPart(language) || 'en'}/cards/${doubledId}/${slug}`;
}

function redirectPaths(row, slug = cardDetailSlug(row), language = 'en') {
  const blueprintId = String(row.blueprint_id || '').trim();
  const cleanLanguage = slugPart(language) || 'en';
  return [
    `/marketplace/${cleanLanguage}/cards/${blueprintId}`,
    `/marketplace/${cleanLanguage}/cards/${blueprintId}-${slug}`,
    `/${blueprintId}`,
  ];
}

function rowFailureSummary(row, slug) {
  const missing = [];
  const blueprintId = String(row.blueprint_id || '').trim();
  const rarity = row.rarity.toLowerCase();
  const collectorNumber = collectorNumberForUrl(row);
  if (!row.name) missing.push('name');
  if (!row.set_name) missing.push('set');
  if (!row.rarity || rarity === 'card') missing.push('rarity');
  if (!collectorNumber || (blueprintId && collectorNumber === blueprintId)) {
    missing.push('collector_number');
  }

  const invalid = [];
  if (!slug) invalid.push('empty_slug');
  if (slug && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) invalid.push('invalid_slug');
  const path = canonicalPath(row, slug);
  if (!path) invalid.push('empty_canonical_path');
  if (path && !/^\/marketplace\/[a-z0-9-]+\/cards\/[1-9][0-9]*\/[a-z0-9]+(?:-[a-z0-9]+)*$/.test(path)) {
    invalid.push('invalid_canonical_path');
  }
  if (path && !path.includes(`/cards/${doubledBlueprintId(row)}/`)) {
    invalid.push('missing_doubled_id');
  }
  if (
    blueprintId &&
    (slug === blueprintId ||
      slug.startsWith(`${blueprintId}-`) ||
      slug.split('-').includes(blueprintId))
  ) {
    invalid.push('contains_numeric_id');
  }

  return { missing, invalid };
}

function sampleRow(row, extra = {}) {
  return {
    blueprintId: String(row.blueprint_id || ''),
    doubledBlueprintId: doubledBlueprintId(row),
    slug: extra.slug || '',
    canonicalPath: extra.canonicalPath || '',
    name: row.name || '',
    setName: row.set_name || '',
    collectorNumber: collectorNumberForUrl(row),
    rarity: row.rarity || '',
    itemKind: row.item_kind || '',
    productType: row.product_type || '',
    ...extra,
  };
}

function addSample(samples, key, value, limit) {
  if (samples[key].length < limit) samples[key].push(value);
}

function addCount(object, key, amount = 1) {
  object[key] = (object[key] || 0) + amount;
}

async function databaseStatus(pool) {
  const result = await pool.query(`
    select
      current_database() as database_name,
      pg_is_in_recovery() as in_recovery
  `);
  return result.rows[0] || {};
}

async function countEligibleRows(pool, scope) {
  const result = await pool.query(`
    select count(*)::integer as count
    from public.cardtrader_pokemon_blueprints b
    left join public.marketplace_search_candidates c on c.card_id = b.id
    ${scopeWhere(scope)}
  `);
  return Number(result.rows[0]?.count || 0);
}

async function fetchEligibleIds(pool, options) {
  const result = await pool.query(
    `
      select b.id
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c on c.card_id = b.id
      ${scopeWhere(options.scope)}
      order by b.id asc
      offset $1::integer
      limit $2::integer
    `,
    [options.start, options.targetRows],
  );
  return result.rows.map((row) => String(row.id));
}

async function fetchChunk(pool, ids) {
  if (ids.length === 0) return [];
  const result = await pool.query(
    `
      select
        b.id as blueprint_id,
        c.card_id,
        coalesce(nullif(c.name, ''), nullif(c.display_name, ''), nullif(b.name, ''), nullif(b.blueprint->>'name', '')) as name,
        coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) as set_name,
        coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), nullif(b.version, '')) as collector_number,
        b.version,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.homepage_image_url,
        coalesce(nullif(c.rarity, ''), nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', '')) as rarity,
        coalesce(nullif(c.item_kind, ''), 'single') as item_kind,
        coalesce(nullif(c.product_type, ''), 'card') as product_type
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c on c.card_id = b.id
      where b.id = any($1::bigint[])
      order by b.id asc
    `,
    [ids],
  );
  return result.rows.map((row) => ({
    ...row,
    name: cleanText(row.name),
    set_name: cleanText(row.set_name),
    collector_number: cleanText(row.collector_number),
    version: cleanText(row.version),
    image_url: cleanText(row.image_url),
    cdn_image_url: cleanText(row.cdn_image_url),
    preview_image_url: cleanText(row.preview_image_url),
    homepage_image_url: cleanText(row.homepage_image_url),
    rarity: cleanText(row.rarity),
    item_kind: cleanText(row.item_kind),
    product_type: cleanText(row.product_type),
  }));
}

async function runChunkWorkers(pool, options, chunkIds) {
  const chunkCount = chunkIds.length;
  const chunks = new Array(chunkCount);
  const errors = [];
  let nextChunk = 0;
  let completed = 0;

  async function worker() {
    while (true) {
      const chunkIndex = nextChunk;
      nextChunk += 1;
      if (chunkIndex >= chunkCount) return;
      try {
        chunks[chunkIndex] = await fetchChunk(pool, chunkIds[chunkIndex]);
      } catch (error) {
        errors.push({
          chunkIndex,
          firstId: chunkIds[chunkIndex]?.[0] || '',
          lastId: chunkIds[chunkIndex]?.[chunkIds[chunkIndex].length - 1] || '',
          message: error.message || String(error),
          code: error.code || '',
        });
        chunks[chunkIndex] = [];
      } finally {
        completed += 1;
        if (completed === chunkCount || completed % options.progressEvery === 0) {
          console.error(`progress chunks=${completed}/${chunkCount}`);
        }
      }
    }
  }

  const workerCount = Math.min(options.concurrency, chunkCount);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return { chunks, errors };
}

function chunkArray(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

function summarizeRows(chunks, options) {
  const pathOwners = new Map();
  const duplicatePathKeys = new Set();
  const duplicateRowIds = new Set();
  const counts = {
    checked: 0,
    duplicatePaths: 0,
    duplicateRows: 0,
    invalidSlugs: 0,
    invalidPaths: 0,
    redirectCompatibility: 0,
    genericRarity: 0,
    missingFields: {
      name: 0,
      set: 0,
      rarity: 0,
      collector_number: 0,
    },
  };
  const samples = {
    duplicates: [],
    missingFields: [],
    invalidSlugs: [],
    genericRarity: [],
  };

  for (const rows of chunks) {
    for (const row of rows || []) {
      const slug = cardDetailSlug(row);
      const path = canonicalPath(row, slug);
      const failure = rowFailureSummary(row, slug);
      counts.checked += 1;

      if (row.rarity.toLowerCase() === 'card') {
        counts.genericRarity += 1;
        addSample(samples, 'genericRarity', sampleRow(row, { slug }), options.sampleLimit);
      }
      for (const field of failure.missing) {
        counts.missingFields[field] += 1;
      }
      if (failure.missing.length > 0) {
        addSample(
          samples,
          'missingFields',
          sampleRow(row, { slug, missing: failure.missing }),
          options.sampleLimit,
        );
      }
      if (failure.invalid.length > 0) {
        counts.invalidSlugs += 1;
        if (failure.invalid.some((key) => key.includes('path') || key === 'missing_doubled_id')) {
          counts.invalidPaths += 1;
        }
        addSample(
          samples,
          'invalidSlugs',
          sampleRow(row, { slug, canonicalPath: path, invalid: failure.invalid }),
          options.sampleLimit,
        );
      }

      const redirects = redirectPaths(row, slug);
      if (
        redirects.length !== 3 ||
        redirects.some((redirectPath) => !redirectPath.includes(String(row.blueprint_id || '').trim()))
      ) {
        counts.redirectCompatibility += 1;
      }

      const existing = pathOwners.get(path);
      if (existing) {
        duplicatePathKeys.add(path);
        duplicateRowIds.add(String(existing.blueprint_id));
        duplicateRowIds.add(String(row.blueprint_id));
        addSample(
          samples,
          'duplicates',
          {
            canonicalPath: path,
            first: sampleRow(existing, { slug: cardDetailSlug(existing), canonicalPath: path }),
            duplicate: sampleRow(row, { slug, canonicalPath: path }),
          },
          options.sampleLimit,
        );
      } else {
        pathOwners.set(path, row);
      }
    }
  }

  counts.duplicatePaths = duplicatePathKeys.size;
  counts.duplicateRows = duplicateRowIds.size;
  counts.pathOwners = pathOwners.size;
  return { counts, samples };
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const pool = new Pool(marketplaceDatabaseConfig(options));
  try {
    const [status, eligibleRows] = await Promise.all([
      databaseStatus(pool),
      countEligibleRows(pool, options.scope),
    ]);
    const availableRows = Math.max(eligibleRows - options.start, 0);
    const chunkLimit = options.chunks == null ? availableRows : options.chunks * options.chunkSize;
    const targetRows = Math.min(
      availableRows,
      options.limit == null ? chunkLimit : Math.min(options.limit, chunkLimit),
    );
    const runOptions = { ...options, targetRows };
    const eligibleIds = await fetchEligibleIds(pool, runOptions);
    const chunkIds = chunkArray(eligibleIds, options.chunkSize);
    const chunkCount = chunkIds.length;

    console.error(JSON.stringify({
      mode: 'read-only',
      scope: options.scope,
      eligibleRows,
      targetRows,
      chunkSize: options.chunkSize,
      chunkCount,
      concurrency: options.concurrency,
      poolMax: options.poolMax,
    }));

    const startedAt = Date.now();
    const { chunks, errors } = await runChunkWorkers(pool, runOptions, chunkIds);
    const summary = summarizeRows(chunks, options);
    const output = {
      generatedAt: new Date().toISOString(),
      mode: 'read-only',
      target: 'oracle:marketplace canonical card URLs',
      database: {
        name: status.database_name,
        inRecovery: Boolean(status.in_recovery),
      },
      options: {
        scope: options.scope,
        chunkSize: options.chunkSize,
        chunks: options.chunks == null ? 'all' : options.chunks,
        start: options.start,
        limit: options.limit == null ? 'all' : options.limit,
        concurrency: options.concurrency,
        poolMax: options.poolMax,
      },
      totals: {
        eligibleRows,
        targetRows,
        chunksRequested: chunkCount,
        chunksCompleted: chunks.filter((chunk) => Array.isArray(chunk) && chunk.length > 0).length,
        durationMs: Date.now() - startedAt,
      },
      checks: {
        requiredFields: ['name', 'set', 'rarity', 'collector_number'],
        canonicalPattern: '/marketplace/en/cards/{blueprintId * 2}/{rarity}-{name}-{collector-number}-{set}',
        uniquenessScope: 'processed canonical path',
        redirectCompatibility: [
          '/marketplace/{lang}/cards/{blueprintId}',
          '/marketplace/{lang}/cards/{blueprintId}-{slug}',
          '/{blueprintId}',
        ],
      },
      counts: summary.counts,
      samples: summary.samples,
      chunkErrors: errors.slice(0, options.sampleLimit),
    };

    console.log(JSON.stringify(output, null, 2));
    if (
      errors.length > 0 ||
      summary.counts.duplicatePaths > 0 ||
      summary.counts.invalidPaths > 0 ||
      summary.counts.redirectCompatibility > 0
    ) {
      process.exitCode = 1;
    }
  } finally {
    await pool.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  cardDetailSlug,
  canonicalPath,
  collectorNumberForUrl,
  doubledBlueprintId,
  parseArgs,
  redirectPaths,
  slugPart,
  rowFailureSummary,
};
