#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

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

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function parseLimit(value) {
  const raw = String(value ?? '100').trim().toLowerCase();
  if (raw === 'all' || raw === 'none') return Infinity;
  const number = Number(raw);
  if (!Number.isFinite(number) || number < 1) {
    throw new Error('--limit must be a positive number or all.');
  }
  return Math.trunc(number);
}

function parsePositiveInt(value, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function parseArgs(argv) {
  const envLimit = process.env.LOGO_MAX_ROWS || process.env.LIMIT;
  const options = {
    apply: process.env.APPLY === '1',
    limit: envLimit ? parseLimit(envLimit) : 100,
    onlyMissing: true,
    cdnBaseUrl: process.env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com',
    bucket: process.env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images',
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const [rawKey, inlineValue] = token.slice(2).split('=', 2);
    const key = rawKey.trim();
    const value = inlineValue !== undefined
      ? inlineValue
      : argv[index + 1] && !argv[index + 1].startsWith('--')
        ? argv[++index]
        : true;
    if (key === 'apply') {
      options.apply = true;
    } else if (key === 'dry-run') {
      options.apply = false;
    } else if (key === 'limit') {
      options.limit = parseLimit(value);
    } else if (key === 'all') {
      options.limit = Infinity;
    } else if (key === 'refresh-existing') {
      options.onlyMissing = false;
    } else if (key === 'cdn-base-url') {
      options.cdnBaseUrl = String(value || '').replace(/\/+$/, '') || options.cdnBaseUrl;
    } else if (key === 'bucket') {
      options.bucket = String(value || '').trim() || options.bucket;
    }
  }
  if (process.env.DRY_RUN === '1') {
    options.apply = false;
  }

  options.cdnBaseUrl = String(options.cdnBaseUrl || 'https://cdn.pokoin.com').replace(/\/+$/, '');
  return options;
}

function createPoolFromEnv() {
  const connectionString = process.env.MARKETPLACE_DATABASE_URL ||
    process.env.MARKETPLACE_PEER4_DATABASE_URL ||
    '';
  const sslVerify = process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1';
  if (connectionString) {
    const sanitizedConnectionString = sslVerify
      ? connectionString
      : connectionString.replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
          prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '',
        ).replace(/[?&]$/, '');
    return new Pool({
      connectionString: sanitizedConnectionString,
      max: 4,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 10_000,
      ssl: { rejectUnauthorized: sslVerify },
      application_name: 'tcgdex-expansion-logo-import',
    });
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
  return new Pool({
    host: process.env.MARKETPLACE_DB_PUBLIC_HOST,
    port: Number(process.env.MARKETPLACE_DB_PORT || 5432),
    database: process.env.MARKETPLACE_DB_NAME,
    user: process.env.MARKETPLACE_DB_USER,
    password: process.env.MARKETPLACE_DB_PASSWORD,
    max: 4,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: sslVerify },
    application_name: 'tcgdex-expansion-logo-import',
  });
}

function createR2Client(env = process.env) {
  for (const key of [
    'CLOUDFLARE_ACCOUNT_ID',
    'R2_ACCESS_KEY_ID',
    'R2_SECRET_ACCESS_KEY',
  ]) {
    if (!env[key]) throw new Error(`Missing ${key}`);
  }
  return new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });
}

async function fetchLogoAsset(sourceUrl) {
  const candidates = logoSourceCandidates(sourceUrl);
  let lastError;
  for (const url of candidates) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        lastError = new Error(`${response.status} ${response.statusText}`.trim());
        continue;
      }
      const contentType = response.headers.get('content-type') || '';
      const body = Buffer.from(await response.arrayBuffer());
      return {
        sourceUrl: url,
        body,
        contentType: contentType.split(';')[0].trim() || contentTypeForExtension(extensionForUrl(url)),
        extension: extensionForUrl(url),
      };
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not fetch logo ${sourceUrl}: ${lastError?.message || 'unknown error'}`);
}

function logoSourceCandidates(sourceUrl) {
  const clean = String(sourceUrl || '').trim();
  if (!clean) return [];
  const url = clean.replace(/\/+$/, '');
  const ext = extensionForUrl(url);
  if (ext !== 'png') return [url];
  if (/\.(png|jpg|jpeg|webp|svg)$/i.test(url)) return [url];
  return [`${url}.png`, url];
}

function extensionForUrl(value) {
  const pathname = (() => {
    try {
      return new URL(value).pathname;
    } catch (_) {
      return String(value || '');
    }
  })();
  const match = pathname.match(/\.([a-z0-9]{2,5})$/i);
  const ext = match ? match[1].toLowerCase() : 'png';
  return ext === 'jpeg' ? 'jpg' : ext;
}

function contentTypeForExtension(ext) {
  if (ext === 'jpg' || ext === 'jpeg') return 'image/jpeg';
  if (ext === 'webp') return 'image/webp';
  if (ext === 'svg') return 'image/svg+xml';
  return 'image/png';
}

async function fetchLogoRows(pool, options) {
  const values = [];
  const expansionWhere = options.onlyMissing
    ? "where coalesce(expansions.logo_image_url, '') = ''"
    : '';
  if (Number.isFinite(options.limit)) {
    values.push(options.limit);
  }
  const limitSql = Number.isFinite(options.limit) ? `limit $${values.length}` : '';
  const result = await pool.query(
    `
      with logo_sources as (
        select distinct on (versions.expansion_name)
          versions.expansion_name,
          metadata.set_name,
          metadata.set_id,
          metadata.set_logo_url,
          count(*) over (partition by versions.expansion_name)::integer as metadata_rows
        from public.marketplace_card_versions versions
        join public.marketplace_blueprint_tcg_metadata metadata
          on metadata.blueprint_id = versions.blueprint_id
        where nullif(metadata.set_logo_url, '') is not null
          and versions.expansion_name is not null
          and versions.expansion_name <> ''
        order by
          versions.expansion_name,
          metadata.confidence desc nulls last,
          metadata.matched_at desc nulls last
      )
      select
        min(expansions.expansion_id) as expansion_id,
        logo_sources.expansion_name as name,
        min(expansions.code) as code,
        min(expansions.logo_image_url) as logo_image_url,
        logo_sources.set_id,
        logo_sources.set_logo_url,
        logo_sources.metadata_rows
      from logo_sources
      join public.cardtrader_pokemon_expansions expansions
        on expansions.name = logo_sources.expansion_name
      ${expansionWhere}
      group by
        logo_sources.expansion_name,
        logo_sources.set_id,
        logo_sources.set_logo_url,
        logo_sources.metadata_rows
      order by logo_sources.expansion_name asc
      ${limitSql}
    `,
    values,
  );
  return result.rows.map((row) => {
    const slug = slugify(row.name);
    const ext = extensionForUrl(row.set_logo_url);
    const objectKey = `expansions/logos/${slug}.${ext}`;
    return {
      expansionId: Number(row.expansion_id),
      name: row.name || '',
      code: row.code || '',
      setId: row.set_id || '',
      sourceLogoUrl: row.set_logo_url || '',
      existingLogoUrl: row.logo_image_url || '',
      metadataRows: Number(row.metadata_rows || 0),
      objectKey,
      logoImageUrl: `${options.cdnBaseUrl}/${objectKey}`,
    };
  });
}

async function updateExpansionLogo(pool, row) {
  await pool.query(
    `
      update public.cardtrader_pokemon_expansions
      set
        logo_image_url = $2,
        logo_object_key = $3,
        logo_imported_at = now()
      where expansion_id = $1
    `,
    [row.expansionId, row.logoImageUrl, row.objectKey],
  );
}

async function importLogos({ pool, r2Client, options }) {
  const rows = await fetchLogoRows(pool, options);
  const samples = [];
  const errors = [];
  let uploaded = 0;
  for (const row of rows) {
    if (samples.length < 8) samples.push(row);
    if (!options.apply) continue;
    try {
      const asset = await fetchLogoAsset(row.sourceLogoUrl);
      await r2Client.send(new PutObjectCommand({
        Bucket: options.bucket,
        Key: row.objectKey,
        Body: asset.body,
        ContentType: asset.contentType,
        CacheControl: 'public, max-age=31536000, immutable',
      }));
      await updateExpansionLogo(pool, row);
      uploaded += 1;
      console.log(`uploaded ${row.expansionId} ${row.code || ''}: ${row.objectKey} <- ${asset.sourceUrl}`);
    } catch (error) {
      errors.push({
        expansionId: row.expansionId,
        name: row.name,
        sourceLogoUrl: row.sourceLogoUrl,
        error: error.message || String(error),
      });
      console.error(`failed ${row.expansionId} ${row.name}: ${error.message || error}`);
    }
  }
  return {
    matched: rows.length,
    uploaded,
    errors,
    samples,
  };
}

async function verifyLogos(pool) {
  const result = await pool.query(`
    select
      count(*) filter (where coalesce(logo_image_url, '') <> '')::integer as rows_with_logo,
      count(*)::integer as expansion_rows,
      max(logo_imported_at) as latest_logo_imported_at
    from public.cardtrader_pokemon_expansions
  `);
  return result.rows[0] || {};
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPoolFromEnv();
  let r2Client = null;
  try {
    if (options.apply) {
      r2Client = createR2Client();
    }
    const result = await importLogos({ pool, r2Client, options });
    const output = {
      mode: options.apply ? 'apply' : 'dry-run',
      target: 'public.cardtrader_pokemon_expansions.logo_image_url',
      cdnPath: 'expansions/logos/<slug>.<ext>',
      options: {
        limit: options.limit === Infinity ? 'all' : options.limit,
        onlyMissing: options.onlyMissing,
        bucket: options.bucket,
        cdnBaseUrl: options.cdnBaseUrl,
      },
      ...result,
    };
    if (options.apply) {
      output.verification = await verifyLogos(pool);
    }
    console.log(JSON.stringify(output, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply to upload logos to R2 and update expansion rows.');
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
  contentTypeForExtension,
  extensionForUrl,
  fetchLogoRows,
  logoSourceCandidates,
  parseArgs,
  slugify,
};
