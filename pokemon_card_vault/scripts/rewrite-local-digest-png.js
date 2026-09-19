#!/usr/bin/env node
'use strict';

/**
 * Rewrite the local CDN digest to lossless PNG siblings on R2.
 *
 * For each leftover key in the digest:
 *   1. If the live R2 object exists, CopyObject to originals/{key} once.
 *   2. Sanitize locally (hard die-cut, lossless PNG).
 *   3. PutObject the sibling {same prefix}.png. Never delete the live JPEG/WebP.
 *   4. Point catalog rows at the PNG by ct_id (no projection refresh).
 *
 * Scope is this digest only. Public URLs stay our id; leftover keys stay ct_id.
 */

const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const { prepareCatalogImage } = require('./lib/sanitize-card-image');
const {
  backupExistingObject,
  siblingPngKey,
} = require('./lib/backup-r2-original');

const DEFAULT_DIGEST = '/home/nez/pokoincdn/cdn_images_digest/2026-08-30';
const DEFAULT_OUT = '/home/nez/pokoincdn/cdn_images_digest/2026-08-30-png';

function readEnv(filePath) {
  const values = {};
  if (!fs.existsSync(filePath)) {
    return values;
  }
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
      continue;
    }
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

function required(env, key) {
  if (!env[key]) {
    throw new Error(`Missing ${key}`);
  }
  return env[key];
}

function parseArgs(argv) {
  const options = {
    apply: false,
    db: true,
    limit: 0,
    concurrency: 3,
    digest: DEFAULT_DIGEST,
    out: DEFAULT_OUT,
    errorLimit: 20,
    only: [],
    catalogLog: '',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--dry-run') {
      options.apply = false;
    } else if (arg === '--no-db') {
      options.db = false;
    } else if (arg === '--only') {
      options.only = String(argv[i + 1] || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      i += 1;
    } else if (arg === '--limit') {
      options.limit = Number(argv[i + 1] || 0);
      i += 1;
    } else if (arg === '--concurrency') {
      options.concurrency = Number(argv[i + 1] || 3);
      i += 1;
    } else if (arg === '--digest') {
      options.digest = String(argv[i + 1] || '').trim();
      i += 1;
    } else if (arg === '--out') {
      options.out = String(argv[i + 1] || '').trim();
      i += 1;
    } else if (arg === '--error-limit') {
      options.errorLimit = Number(argv[i + 1] || 20);
      i += 1;
    } else if (arg === '--catalog-log') {
      options.catalogLog = String(argv[i + 1] || '').trim();
      i += 1;
    }
  }
  return options;
}

function listDigestKeys(root) {
  const out = [];
  function walk(dir, prefix) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) {
        continue;
      }
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        if (entry.name === 'originals') {
          continue;
        }
        walk(path.join(dir, entry.name), rel);
        continue;
      }
      if (!entry.isFile()) {
        continue;
      }
      if (!/\.(jpe?g|png|webp)$/i.test(entry.name)) {
        continue;
      }
      if (/_homepage\.webp$/i.test(entry.name)) {
        continue;
      }
      out.push(rel.replace(/\\/g, '/'));
    }
  }
  walk(root, '');
  return out.sort();
}

function ctIdFromKey(key) {
  const base = String(key || '').replace(/^previews\//, '');
  const match = base.match(/^(\d+)_/);
  return match ? match[1] : null;
}

function contentTypeForPng() {
  return 'image/png';
}

function writeLocalCopy(outDir, key, body) {
  if (!outDir) {
    return;
  }
  const dest = path.join(outDir, key);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, body);
}

function appendLog(logPath, record) {
  fs.appendFileSync(logPath, `${JSON.stringify(record)}\n`);
}

async function updateCatalog(pool, { ctId, isPreview, pngKey, cdnUrl }) {
  const id = Number(ctId);
  if (!Number.isSafeInteger(id) || id <= 0) {
    return { updated: false, reason: 'bad-id' };
  }
  if (isPreview) {
    await pool.query(
      `update public.cardtrader_pokemon_blueprints
       set preview_image_url = $1, preview_object_key = $2
       where id = $3`,
      [cdnUrl, pngKey, id],
    );
    for (const table of [
      'marketplace_cards',
      'marketplace_card_versions',
      'marketplace_search_candidates',
    ]) {
      await pool.query(
        `update public.${table}
         set preview_image_url = $1, projected_at = now()
         where ct_id = $2`,
        [cdnUrl, id],
      );
    }
    return { updated: true };
  }
  await pool.query(
    `update public.cardtrader_pokemon_blueprints
     set image_url = $1, cdn_image_url = $1, cdn_object_key = $2
     where id = $3`,
    [cdnUrl, pngKey, id],
  );
  for (const table of [
    'marketplace_cards',
    'marketplace_card_versions',
    'marketplace_search_candidates',
  ]) {
    await pool.query(
      `update public.${table}
       set image_url = $1, cdn_image_url = $1, projected_at = now()
       where ct_id = $2`,
      [cdnUrl, id],
    );
  }
  return { updated: true };
}

async function rewriteOne({
  client,
  pool,
  bucket,
  cdnBase,
  digest,
  outDir,
  key,
  apply,
  db,
  sharp,
}) {
  const pngKey = siblingPngKey(key);
  const ctId = ctIdFromKey(key);
  const isPreview = key.startsWith('previews/');
  if (!pngKey || !ctId) {
    return { key, status: 'skipped', reason: 'not-a-card-key' };
  }
  const sourcePath = path.join(digest, key);
  const source = fs.readFileSync(sourcePath);
  const sourceExt = path.extname(key).slice(1).toLowerCase();
  const prepared = await prepareCatalogImage(source, sourceExt, { sharp });
  if (prepared.skipped) {
    return { key, pngKey, status: 'skipped', reason: prepared.reason || 'not-a-card' };
  }
  writeLocalCopy(outDir, pngKey, prepared.body);
  const cdnUrl = `${cdnBase}/${pngKey}`;
  if (!apply) {
    return {
      key,
      pngKey,
      status: 'dry-run',
      bytes: prepared.body.length,
      punched: prepared.punched,
      width: prepared.width,
      height: prepared.height,
    };
  }
  const backup = await backupExistingObject(client, { bucket, key });
  if (pngKey !== key) {
    await backupExistingObject(client, { bucket, key: pngKey });
  }
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: pngKey,
      Body: prepared.body,
      ContentType: contentTypeForPng(),
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );
  let catalog = { updated: false, reason: 'disabled' };
  if (db && pool) {
    catalog = await updateCatalog(pool, { ctId, isPreview, pngKey, cdnUrl });
  }
  return {
    key,
    pngKey,
    status: 'ok',
    backup: backup.reason || (backup.backedUp ? 'copied' : 'none'),
    originalsKey: backup.originalsKey || null,
    bytes: prepared.body.length,
    punched: prepared.punched,
    catalog: catalog.updated ? 'updated' : catalog.reason,
  };
}

async function mapLimit(items, concurrency, fn) {
  const results = new Array(items.length);
  let next = 0;
  async function worker() {
    while (true) {
      const index = next;
      next += 1;
      if (index >= items.length) {
        return;
      }
      results[index] = await fn(items[index], index);
    }
  }
  const n = Math.max(1, Math.min(concurrency, items.length || 1));
  await Promise.all(Array.from({ length: n }, () => worker()));
  return results;
}

async function applyCatalogFromLog(logPath, env) {
  required(env, 'MARKETPLACE_DATABASE_URL');
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const pool = new Pool({
    connectionString: env.MARKETPLACE_DATABASE_URL,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 15_000,
    ssl: { rejectUnauthorized: false },
  });
  const summary = { total: 0, updated: 0, skipped: 0, failed: 0 };
  try {
    const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      const row = JSON.parse(line);
      summary.total += 1;
      if (row.status !== 'ok' || !row.pngKey) {
        summary.skipped += 1;
        continue;
      }
      const ctId = ctIdFromKey(row.key || row.pngKey);
      const isPreview = String(row.pngKey).startsWith('previews/');
      const cdnUrl = `${cdnBase}/${row.pngKey}`;
      try {
        await updateCatalog(pool, { ctId, isPreview, pngKey: row.pngKey, cdnUrl });
        summary.updated += 1;
      } catch (error) {
        summary.failed += 1;
        console.error(JSON.stringify({ key: row.key, status: 'failed', error: error.message }));
      }
    }
  } finally {
    await pool.end();
  }
  console.log(JSON.stringify({ catalog: summary, logPath }));
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const env = {
    ...readEnv(path.resolve(__dirname, '../.env.local')),
    ...process.env,
  };
  if (options.catalogLog) {
    await applyCatalogFromLog(path.resolve(options.catalogLog), env);
    return;
  }
  const digest = path.resolve(options.digest || env.ORACLE_IMAGE_DIGEST_DIR || DEFAULT_DIGEST);
  const outDir = path.resolve(options.out || env.ORACLE_IMAGE_PNG_DIR || DEFAULT_OUT);
  if (!fs.existsSync(digest)) {
    throw new Error(`digest not found: ${digest}`);
  }
  let keys = listDigestKeys(digest);
  if (options.only.length > 0) {
    const wanted = new Set(options.only);
    keys = keys.filter((key) => wanted.has(key));
    const missing = options.only.filter((key) => !keys.includes(key));
    if (missing.length) {
      throw new Error(`not in digest: ${missing.join(', ')}`);
    }
  }
  if (options.limit > 0) {
    keys = keys.slice(0, options.limit);
  }
  fs.mkdirSync(outDir, { recursive: true });
  const logPath = path.join(outDir, 'rewrite.log.jsonl');

  let sharp;
  try {
    sharp = require('sharp');
  } catch (error) {
    throw new Error(`sharp is required: ${error.message}`);
  }

  const apply = options.apply;
  if (apply && String(env.ORACLE_IMAGE_ALLOW_PNG || '') !== '1') {
    throw new Error(
      'D00000E: lossless catalog PNG is not viable. Refusing --apply. Catalog stays JPEG/WebP.',
    );
  }
  if (apply) {
    required(env, 'CLOUDFLARE_ACCOUNT_ID');
    required(env, 'R2_ACCESS_KEY_ID');
    required(env, 'R2_SECRET_ACCESS_KEY');
  }
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const client = apply
    ? new S3Client({
        region: 'auto',
        endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
        credentials: {
          accessKeyId: env.R2_ACCESS_KEY_ID,
          secretAccessKey: env.R2_SECRET_ACCESS_KEY,
        },
      })
    : null;
  const pool =
    apply && options.db && env.MARKETPLACE_DATABASE_URL
      ? new Pool({
          connectionString: env.MARKETPLACE_DATABASE_URL,
          max: 2,
          idleTimeoutMillis: 10_000,
          connectionTimeoutMillis: 10_000,
          ssl: { rejectUnauthorized: false },
        })
      : null;

  const summary = {
    digest,
    apply,
    db: Boolean(pool),
    total: keys.length,
    ok: 0,
    dryRun: 0,
    skipped: 0,
    failed: 0,
    backedUp: 0,
  };

  console.log(
    JSON.stringify({
      start: true,
      digest,
      outDir,
      apply,
      db: Boolean(pool),
      total: keys.length,
      concurrency: options.concurrency,
    }),
  );

  try {
    await mapLimit(keys, options.concurrency, async (key, index) => {
      try {
        const result = await rewriteOne({
          client,
          pool,
          bucket,
          cdnBase,
          digest,
          outDir,
          key,
          apply,
          db: Boolean(pool),
          sharp,
        });
        if (result.status === 'ok') {
          summary.ok += 1;
          if (result.backup === 'copied') {
            summary.backedUp += 1;
          }
        } else if (result.status === 'dry-run') {
          summary.dryRun += 1;
        } else {
          summary.skipped += 1;
        }
        appendLog(logPath, { ...result, index });
        if ((index + 1) % 25 === 0 || index === 0) {
          console.log(JSON.stringify({ progress: index + 1, ...summary, last: result.key }));
        }
        return result;
      } catch (error) {
        summary.failed += 1;
        const record = {
          key,
          status: 'failed',
          error: error.message,
          index,
        };
        appendLog(logPath, record);
        console.error(JSON.stringify(record));
        if (summary.failed >= options.errorLimit) {
          throw new Error(`stopping after ${summary.failed} errors`);
        }
        return record;
      }
    });
  } finally {
    if (pool) {
      await pool.end();
    }
  }

  console.log(JSON.stringify({ summary, logPath }));
  if (!apply) {
    console.log('dry-run only; pass --apply to backup live keys and PutObject sibling PNGs');
  }
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

module.exports = {
  DEFAULT_DIGEST,
  siblingPngKey,
  listDigestKeys,
  ctIdFromKey,
  parseArgs,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
