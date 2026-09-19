#!/usr/bin/env node

/**
 * Pull pokemontcg.io hires PNGs (always the official scan, never the live
 * catalog JPEG) for marketplace expansions marked download, encode catalog
 * JPEG (q100 4:4:4), backup live R2 to originals/{key} once, PutObject leftover
 * {ct_id}_ keys, point catalog URLs at cdn.pokoin.com.
 *
 * Never writes PNG. Never runs projection refresh. JP-named expansions skip.
 * Gold HR leftover keys omit `hyper-rare` — `sanitizeCardImage` must detect
 * foil-to-edge from pixels (isGoldFoilRaster), not the filename.
 *
 *   node scripts/import-pokemontcg-expansion-hires.js
 *   node scripts/import-pokemontcg-expansion-hires.js --apply
 *   node scripts/import-pokemontcg-expansion-hires.js --apply --force
 *   node scripts/import-pokemontcg-expansion-hires.js --apply --force --expansion="POP Series 6" --cache-bust=br4
 *   node scripts/import-pokemontcg-expansion-hires.js --apply --force --expansion="Phantasmal Flames" --number=84 --cache-bust=r8
 *   node scripts/import-pokemontcg-expansion-hires.js --apply --expansion=Black Bolt
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const sharp = require('sharp');
const { leftoverCdnObjectKey } = require('./lib/cdn-object-key');
const { backupExistingObject } = require('./lib/backup-r2-original');
const { DEFAULT_LOCAL_CDN, writeLocalCdnObject } = require('./lib/local-cdn');
const { sanitizeCardImage } = require('./lib/sanitize-card-image');
const {
  resolvePokemontcgHires,
  absoluteCdnUrl,
  pngDimensionsFromPrefix,
  isBetterDefinition,
  catalogJpegFromPokemontcgPng,
} = require('./lib/pokemontcg-hires');

const API = 'https://api.pokoin.com/api/marketplace-expansion-page';
const DEFAULT_REPORT = '/tmp/pokemontcg-expansion-samples/expansion-sample-compare.json';
const DEFAULT_OUT = '/tmp/pokemontcg-expansion-jpg';
const UA = 'Pokoin pokemontcg expansion jpeg import';
const CDN_HOST = 'cdn.pokoin.com';

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
    values[key] = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
  }
  return values;
}

function marketplaceDatabaseUrl(env) {
  const raw = String(env.MARKETPLACE_DATABASE_URL || '');
  if (!raw) {
    throw new Error('Missing MARKETPLACE_DATABASE_URL');
  }
  const host = String(env.MARKETPLACE_DB_HOST_OVERRIDE || '').trim();
  if (!host) {
    return raw;
  }
  const parsed = new URL(raw);
  parsed.hostname = host;
  if (env.MARKETPLACE_DB_PORT_OVERRIDE) {
    parsed.port = String(env.MARKETPLACE_DB_PORT_OVERRIDE);
  }
  return parsed.toString();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: Infinity,
    out: DEFAULT_OUT,
    report: DEFAULT_REPORT,
    concurrency: 16,
    expansion: '',
    force: false,
    cacheBust: '',
    number: '',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--force') {
      options.force = true;
    } else if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, Number(arg.slice('--limit='.length)) || 1);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length) || DEFAULT_OUT;
    } else if (arg.startsWith('--report=')) {
      options.report = arg.slice('--report='.length) || DEFAULT_REPORT;
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, Math.min(24, Number(arg.slice('--concurrency='.length)) || 12));
    } else if (arg.startsWith('--cache-bust=')) {
      options.cacheBust = arg.slice('--cache-bust='.length).replace(/[^a-zA-Z0-9._-]/g, '');
    } else if (arg.startsWith('--expansion=')) {
      options.expansion = arg.slice('--expansion='.length);
    } else if (arg.startsWith('--number=')) {
      options.number = arg.slice('--number='.length).trim();
    }
  }
  return options;
}

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function isJapaneseExpansion(name) {
  return /\b(?:jp|japanese)\b/i.test(String(name || ''));
}

function collectorNumberMatches(hires, card, want) {
  if (!want) {
    return true;
  }
  const norm = (value) => String(value || '').trim().replace(/^0+(\d)/, '$1').toLowerCase();
  const target = norm(want);
  if (!target) {
    return true;
  }
  return [hires && hires.number, card.number, card.card_number, card.collectorNumber]
    .map(norm)
    .some((value) => value === target);
}

function isPreviewUrl(url) {
  const text = String(url || '');
  return /\/preview_/i.test(text) || /\/previews\//i.test(text);
}

function preferCatalogImageUrl(card = {}) {
  const urls = [
    card.heroImageUrl,
    card.gridImageUrl,
    card.imageUrl,
    card.cdnImageUrl,
    card.image_url,
  ]
    .map((value) => absoluteCdnUrl(value))
    .filter(Boolean);
  const cdnFull = urls.find((url) => url.includes(CDN_HOST) && !isPreviewUrl(url));
  if (cdnFull) {
    return cdnFull;
  }
  const anyFull = urls.find((url) => !isPreviewUrl(url));
  return anyFull || urls[0] || '';
}

function leftoverKeyFromImageUrl(url, ctId) {
  const abs = absoluteCdnUrl(url);
  if (!abs || !abs.includes(CDN_HOST)) {
    return null;
  }
  let key = '';
  try {
    key = new URL(abs).pathname.replace(/^\/+/, '');
  } catch {
    return null;
  }
  if (!key) {
    return null;
  }
  const prefix = `${ctId}_`;
  if (key.startsWith(prefix) || key.startsWith(`previews/${prefix}`)) {
    return key.replace(/\.[^.]+$/, '.jpg');
  }
  const leftover = leftoverCdnObjectKey(key);
  if (
    leftover &&
    (leftover.startsWith(prefix) || leftover.startsWith(`previews/${prefix}`))
  ) {
    return leftover.replace(/\.[^.]+$/, '.jpg');
  }
  if (/^(previews\/)?\d+_/.test(key)) {
    return key.replace(/\.[^.]+$/, '.jpg');
  }
  return null;
}

function catalogObjectKey(card) {
  const ctId = String(card.ct_id || card.ctId || '').trim();
  const slug = slugify(card.name) || `card-${ctId}`;
  const fromUrl = leftoverKeyFromImageUrl(preferCatalogImageUrl(card), ctId);
  if (fromUrl && !fromUrl.startsWith('previews/')) {
    return fromUrl;
  }
  return `${ctId}_${slug}.jpg`;
}

function previewObjectKey(card) {
  const ctId = String(card.ct_id || card.ctId || '').trim();
  const slug = slugify(card.name) || `card-${ctId}`;
  return `previews/${ctId}_${slug}.jpg`;
}

function samePixelSize(api, ours) {
  return Boolean(api && ours && api.width === ours.width && api.height === ours.height);
}

/** Live catalog after pad (Gible 600→622). --force must still re-encode. */
function isPaddedCatalogOf(api, ours) {
  if (!api || !ours || !api.width || !ours.width) {
    return false;
  }
  const dw = ours.width - api.width;
  const dh = ours.height - api.height;
  if (dw < 0 || dh < 0 || Math.abs(dw - dh) > 2) {
    return false;
  }
  const pad = dw / 2;
  return pad <= Math.round(api.width * 0.08) + 2;
}

function shouldReplaceCatalog(api, ours, { force } = {}) {
  const catalog = ours && ours.preview ? null : ours;
  if (isBetterDefinition(api, catalog)) {
    return true;
  }
  if (!force) {
    return false;
  }
  return samePixelSize(api, catalog) || isPaddedCatalogOf(api, catalog);
}

function loadDownloadExpansions(reportPath, onlyName) {
  const payload = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  const rows = (payload.rows || []).filter((row) => {
    if (row.action !== 'download' || !row.setId) {
      return false;
    }
    if (isJapaneseExpansion(row.expansion)) {
      return false;
    }
    if (onlyName && String(row.expansion).toLowerCase() !== onlyName.toLowerCase()) {
      return false;
    }
    return true;
  });
  return rows.map((row) => ({
    name: row.expansion,
    slug: row.slug || '',
    setId: row.setId,
    cardCount: row.cardCount || 0,
  }));
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': UA } });
  if (!response.ok) {
    throw new Error(`${response.status} ${url}`);
  }
  return response.json();
}

async function fetchBuffer(url, range) {
  const headers = { 'User-Agent': UA };
  if (range) {
    headers.Range = range;
  }
  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`${response.status} ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function pngSize(url, cache) {
  if (cache.has(url)) {
    return cache.get(url);
  }
  const prefix = await fetchBuffer(url, 'bytes=0-31');
  const size = pngDimensionsFromPrefix(prefix);
  cache.set(url, size);
  return size;
}

async function jpegSize(url, cache) {
  if (!url) {
    return null;
  }
  if (isPreviewUrl(url)) {
    return { width: 180, height: 250, preview: true };
  }
  if (cache.has(url)) {
    return cache.get(url);
  }
  try {
    const prefix = await fetchBuffer(url, 'bytes=0-131071');
    const meta = await sharp(prefix, { failOn: 'none' }).metadata();
    const size = meta.width && meta.height
      ? { width: meta.width, height: meta.height, bytes: body.length }
      : null;
    cache.set(url, size);
    return size;
  } catch {
    cache.set(url, null);
    return null;
  }
}

async function listExpansionCards(expansion) {
  const cards = [];
  let offset = 0;
  const pageSize = 400;
  for (;;) {
    const params = new URLSearchParams({
      productType: 'card',
      limit: String(pageSize),
      offset: String(offset),
      expansionName: expansion.name,
    });
    const payload = await fetchJson(`${API}?${params}`);
    const page = (payload.cards || []).filter((card) => String(card.productType || 'card') === 'card');
    cards.push(...page);
    if (page.length < pageSize) {
      break;
    }
    offset += pageSize;
    if (offset > 8000) {
      break;
    }
  }
  return cards;
}

async function mapPool(items, concurrency, worker) {
  const results = new Array(items.length);
  let index = 0;
  async function run() {
    while (index < items.length) {
      const current = index;
      index += 1;
      results[current] = await worker(items[current], current);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, Math.max(1, items.length)) }, () => run()));
  return results;
}

async function updateMarketplaceImageUrls(pool, ctId, updates) {
  const id = Number(ctId);
  await pool.query(
    `
      update public.cardtrader_pokemon_blueprints
      set
        image_url = coalesce($1, image_url),
        cdn_image_url = coalesce($2, cdn_image_url),
        cdn_object_key = coalesce($3, cdn_object_key),
        preview_image_url = coalesce($4, preview_image_url),
        preview_object_key = coalesce($5, preview_object_key)
      where id = $6
    `,
    [
      updates.image_url,
      updates.cdn_image_url,
      updates.cdn_object_key,
      updates.preview_image_url,
      updates.preview_object_key,
      id,
    ],
  );
  const params = [updates.image_url, updates.cdn_image_url, updates.preview_image_url, id];
  for (const table of ['marketplace_cards', 'marketplace_card_versions', 'marketplace_search_candidates']) {
    await pool.query(
      `
        update public.${table}
        set
          image_url = coalesce($1, image_url),
          cdn_image_url = coalesce($2, cdn_image_url),
          preview_image_url = coalesce($3, preview_image_url),
          projected_at = now()
        where ct_id = $4
      `,
      params,
    );
  }
}

async function catalogPreviewJpeg(fullJpeg) {
  return sharp(fullJpeg, { failOn: 'none' })
    .rotate()
    .resize({ width: 180, height: 251, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85, mozjpeg: true })
    .toBuffer();
}

function writeProgress(outDir, obj) {
  const line = `${JSON.stringify(obj)}\n`;
  try {
    process.stdout.write(line);
  } catch (_) {
    /* ignore */
  }
  fs.mkdirSync(outDir, { recursive: true });
  fs.appendFileSync(path.join(outDir, 'progress.jsonl'), line);
}

function writeLocalCopy(localDir, key, body) {
  if (!localDir) {
    return;
  }
  const dest = path.join(localDir, key);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, body);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const env = { ...process.env, ...readEnv(path.resolve(__dirname, '../.env.local')) };
  const expansions = loadDownloadExpansions(options.report, options.expansion);
  if (!expansions.length) {
    throw new Error(`no download expansions in ${options.report}`);
  }
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const pngCache = new Map();
  const jpegCache = new Map();
  const encode = new Map();
  const stats = {
    expansions: expansions.length,
    cards: 0,
    better: 0,
    skipped: 0,
    wrote: 0,
    uploaded: 0,
    missing: 0,
    errors: 0,
    apply: options.apply,
  };
  const log = [];

  fs.mkdirSync(options.out, { recursive: true });

  let client = null;
  let pool = null;
  if (options.apply) {
    if (!env.CLOUDFLARE_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
      throw new Error('Missing R2 credentials');
    }
    if (!env.MARKETPLACE_DATABASE_URL) {
      throw new Error('Missing MARKETPLACE_DATABASE_URL');
    }
    client = new S3Client({
      region: 'auto',
      endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      },
    });
    pool = new Pool({
      connectionString: marketplaceDatabaseUrl(env),
      ssl: { rejectUnauthorized: false },
      max: Math.max(8, options.concurrency + 2),
    });
  }

  try {
    for (const expansion of expansions) {
      if (stats.wrote >= options.limit) {
        break;
      }
      let cards = [];
      try {
        cards = await listExpansionCards(expansion);
      } catch (error) {
        stats.errors += 1;
        log.push({ expansion: expansion.name, error: String(error.message || error) });
        continue;
      }
      stats.cards += cards.length;
      const beforeWrote = stats.wrote;
      const beforeSkipped = stats.skipped;
      const beforeErrors = stats.errors;
      const jobs = [];
      for (const card of cards) {
        if (!card.ct_id) {
          stats.skipped += 1;
          continue;
        }
        const hires = resolvePokemontcgHires({
          ...card,
          set: expansion.name,
          setId: expansion.setId,
          number: card.number || card.card_number,
        });
        if (!hires.url) {
          stats.skipped += 1;
          continue;
        }
        if (!collectorNumberMatches(hires, card, options.number)) {
          continue;
        }
        jobs.push({ card, expansion, hires });
      }
      const jobConcurrency = Number.isFinite(options.limit)
        ? 1
        : options.concurrency;
      await mapPool(jobs, jobConcurrency, async (job) => {
        if (stats.wrote >= options.limit) {
          return;
        }
        try {
          const apiSize = await pngSize(job.hires.url, pngCache);
          if (!apiSize) {
            stats.missing += 1;
            return;
          }
          const oursUrl = preferCatalogImageUrl(job.card);
          const ours = await jpegSize(oursUrl, jpegCache);
          if (!shouldReplaceCatalog(apiSize, ours, { force: options.force })) {
            stats.skipped += 1;
            return;
          }
          stats.better += 1;
          const sharedKey = `${job.hires.setId}-${job.hires.number}`;
          if (!encode.has(sharedKey)) {
            encode.set(
              sharedKey,
              (async () => {
                const png = await fetchBuffer(job.hires.url);
                return catalogJpegFromPokemontcgPng(png, {
                  sharp,
                  sanitizeCardImage,
                  filename: catalogObjectKey(job.card),
                });
              })(),
            );
          }
          const encoded = await encode.get(sharedKey);
          const key = catalogObjectKey(job.card);
          const previewKey = previewObjectKey(job.card);
          writeLocalCopy(options.out, key, encoded.body);
          const previewBody = await catalogPreviewJpeg(encoded.body);
          writeLocalCopy(options.out, previewKey, previewBody);
          stats.wrote += 1;
          if (stats.wrote === 1 || stats.wrote % 25 === 0) {
            writeProgress(options.out, {
              heartbeat: true,
              expansion: job.expansion.name,
              totalWrote: stats.wrote,
              totalErrors: stats.errors,
            });
          }
          const row = {
            id: job.card.id,
            ct_id: job.card.ct_id,
            name: job.card.name,
            set: job.expansion.name,
            number: job.hires.number,
            api: `${apiSize.width}x${apiSize.height}`,
            ours: ours ? `${ours.width}x${ours.height}` : 'missing',
            key,
          };
          if (!options.apply) {
            log.push(row);
            return;
          }
          await backupExistingObject(client, { bucket, key });
          await client.send(
            new PutObjectCommand({
              Bucket: bucket,
              Key: key,
              Body: encoded.body,
              ContentType: 'image/jpeg',
              CacheControl: 'public, max-age=31536000, immutable',
            }),
          );
          await backupExistingObject(client, { bucket, key: previewKey });
          await client.send(
            new PutObjectCommand({
              Bucket: bucket,
              Key: previewKey,
              Body: previewBody,
              ContentType: 'image/jpeg',
              CacheControl: 'public, max-age=31536000, immutable',
            }),
          );
          const bust = options.cacheBust ? `?v=${options.cacheBust}` : '';
          const url = `${cdnBase}/${key}${bust}`;
          await updateMarketplaceImageUrls(pool, job.card.ct_id, {
            image_url: url,
            cdn_image_url: url,
            cdn_object_key: key,
            preview_image_url: `${cdnBase}/${previewKey}${bust}`,
            preview_object_key: previewKey,
          });
          writeLocalCdnObject(DEFAULT_LOCAL_CDN, key, encoded.body);
          writeLocalCdnObject(DEFAULT_LOCAL_CDN, previewKey, previewBody);
          stats.uploaded += 1;
          log.push({ ...row, uploaded: true });
        } catch (error) {
          stats.errors += 1;
          log.push({
            id: job.card.id,
            name: job.card.name,
            set: job.expansion.name,
            error: String(error.message || error),
          });
        }
      });
      writeProgress(options.out, {
        expansion: expansion.name,
        cards: cards.length,
        wrote: stats.wrote - beforeWrote,
        skipped: stats.skipped - beforeSkipped,
        errors: stats.errors - beforeErrors,
        totalWrote: stats.wrote,
        totalErrors: stats.errors,
      });
    }
  } finally {
    if (pool) {
      await pool.end();
    }
  }

  const reportPath = path.join(options.out, 'pokemontcg-expansion-jpg.json');
  fs.writeFileSync(reportPath, `${JSON.stringify({ ...stats, report: reportPath, sample: log.slice(0, 40), log }, null, 2)}\n`);
  console.log(JSON.stringify({ ...stats, report: reportPath, sample: log.slice(0, 12) }, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  isJapaneseExpansion,
  isPreviewUrl,
  collectorNumberMatches,
  preferCatalogImageUrl,
  leftoverKeyFromImageUrl,
  catalogObjectKey,
  previewObjectKey,
  shouldReplaceCatalog,
  loadDownloadExpansions,
  marketplaceDatabaseUrl,
  updateMarketplaceImageUrls,
  catalogPreviewJpeg,
  readEnv,
};
