#!/usr/bin/env node

/**
 * Listed Base Set leftovers (expansion 1472 / `bs`) were imported from
 * pokemontcg.io `base1` hires. Those scans are 1st Edition / shadowless.
 * CardTrader already stores unlimited TCGPlayer product ids on
 * `pokoin_pokemon_blueprints.tcg_player_ids`. Fetch those product photos and
 * fit them to a 63:88 leftover JPEG. Do not run the yellow-frame millimetre
 * rebuild (`--sanitize`) — that stretched Magneton and left Drowzee as a 325px thumb.
 *
 * Never touches Base Set Shadowless (`shbs` / 1969). Never sealed product
 * rows (boosters / decks).
 *
 *   node scripts/import-base-set-unlimited-tcgplayer.js
 *   node scripts/import-base-set-unlimited-tcgplayer.js --apply --cache-bust=bsu2
 *   node scripts/import-base-set-unlimited-tcgplayer.js --apply --sanitize --ids=111151
 */

'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const sharp = require('sharp');
const { writeLocalCdnObject, DEFAULT_LOCAL_CDN } = require('./lib/local-cdn');
const { backupExistingObject } = require('./lib/backup-r2-original');
const { sanitizeCardImage } = require('./lib/sanitize-card-image');
const { catalogJpegFromPokemontcgPng, CATALOG_JPEG_QUALITY } = require('./lib/pokemontcg-hires');

const LISTED_BASE_SET_EXPANSION_ID = 1472;
const SHADOWLESS_EXPANSION_ID = 1969;
const TCGPLAYER_FIT = 2000;
const HOMEPAGE_WIDTH = 240;
const HOMEPAGE_QUALITY = 82;
/** 63:88 catalog leftover. TCGPlayer fit-in/2000 is already this ratio. */
const CATALOG_WIDTH = 1260;
const CATALOG_HEIGHT = 1760;
const UA = 'Pokoin Base Set unlimited TCGPlayer import';
const CDN_BASE = 'https://cdn.pokoin.com';
const DEFAULT_OUT = '/tmp/pokoin-base-set-unlimited';
const PI_HOST = process.env.POKOIN_PI_HOST || 'pi-home';
const PI_OBJECTS = process.env.POKOIN_PI_OBJECTS || '/srv/pokoin/card-images/objects';
const REPLICA_OBJECTS =
  process.env.POKOIN_REPLICA_OBJECTS || '/home/nez/mnt/mybook/pokoin-pi-card-images/objects';
const PG_CONTAINER = process.env.POKOIN_PG_CONTAINER || 'pokoin-marketplace-postgres-15t';

function parseArgs(argv) {
  const options = {
    apply: false,
    expansionId: LISTED_BASE_SET_EXPANSION_ID,
    fit: TCGPLAYER_FIT,
    out: DEFAULT_OUT,
    concurrency: 4,
    cacheBust: 'bsu1',
    ids: [],
    limit: Infinity,
    push: true,
    sanitize: false,
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--sanitize') {
      options.sanitize = true;
    } else if (arg === '--no-sanitize') {
      options.sanitize = false;
    } else if (arg === '--no-push') {
      options.push = false;
    } else if (arg.startsWith('--expansion-id=')) {
      options.expansionId = Number(arg.slice('--expansion-id='.length)) || LISTED_BASE_SET_EXPANSION_ID;
    } else if (arg.startsWith('--fit=')) {
      options.fit = Math.max(1000, Number(arg.slice('--fit='.length)) || TCGPLAYER_FIT);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length) || DEFAULT_OUT;
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, Math.min(8, Number(arg.slice('--concurrency='.length)) || 4));
    } else if (arg.startsWith('--cache-bust=')) {
      options.cacheBust = arg.slice('--cache-bust='.length).replace(/[^a-zA-Z0-9._-]/g, '') || 'bsu1';
    } else if (arg.startsWith('--ids=')) {
      options.ids = arg
        .slice('--ids='.length)
        .split(',')
        .map((value) => Number(value.trim()))
        .filter((value) => Number.isFinite(value) && value > 0);
    } else if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, Number(arg.slice('--limit='.length)) || 1);
    }
  }
  return options;
}

function assertSanitizeAllowed(options) {
  if (options?.sanitize && !(options.ids && options.ids.length)) {
    throw new Error('Refusing millimetre --sanitize on a full expansion; test with --ids= first');
  }
}

function isListedBaseSetSingle(row) {
  if (Number(row.expansion_id) === SHADOWLESS_EXPANSION_ID) {
    return false;
  }
  if (Number(row.expansion_id) !== LISTED_BASE_SET_EXPANSION_ID) {
    return false;
  }
  return /(?:^|\|\s*)\d{1,3}\s*\/\s*102\b/.test(String(row.version || ''));
}

function firstTcgplayerId(value) {
  if (Array.isArray(value) && value.length) {
    const n = Number(value[0]);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  if (value && typeof value === 'object' && Array.isArray(value.ids) && value.ids.length) {
    const n = Number(value.ids[0]);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function tcgplayerUnlimitedUrl(productId, fit = TCGPLAYER_FIT) {
  const id = Number(productId);
  const size = Math.max(1000, Number(fit) || TCGPLAYER_FIT);
  if (!Number.isFinite(id) || id <= 0) {
    return null;
  }
  return `https://product-images.tcgplayer.com/fit-in/${size}x${size}/${id}.jpg`;
}

function leftoverJpegKey(row) {
  const fromDb = String(row.cdn_object_key || '')
    .replace(/^\/+/, '')
    .split(/[?#]/)[0];
  if (fromDb && /\.jpe?g$/i.test(fromDb) && !fromDb.startsWith('previews/')) {
    return fromDb;
  }
  const fromUrl = String(row.cdn_image_url || row.image_url || '')
    .split(/[?#]/)[0]
    .replace(/^https?:\/\/cdn\.pokoin\.com\//, '')
    .replace(/^\/+/, '');
  if (fromUrl && /\.jpe?g$/i.test(fromUrl) && !fromUrl.startsWith('previews/')) {
    return fromUrl;
  }
  return '';
}

function homepageKeyFor(jpegKey) {
  return String(jpegKey || '').replace(/\.jpe?g$/i, '_homepage.webp');
}

function ctIdAliasKey(ctId, jpegKey) {
  const slug = String(jpegKey || '').replace(/^\d+_/, '');
  if (!ctId || !slug || !/\.jpe?g$/i.test(slug)) {
    return '';
  }
  const alias = `${ctId}_${slug}`;
  return alias === jpegKey ? '' : alias;
}

function previewKeyFor(jpegKey, existing = '') {
  const have = String(existing || '').replace(/^\/+/, '');
  if (have.startsWith('previews/') && /\.jpe?g$/i.test(have)) {
    return have;
  }
  const base = path.posix.basename(String(jpegKey || ''));
  return base ? `previews/${base}` : '';
}

function withCacheBust(url, token) {
  const text = String(url || '').split(/[?#]/)[0];
  if (!text || !token) {
    return text;
  }
  return `${text}?v=${token}`;
}

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

function marketplaceDatabaseUrlFromDocker(container = PG_CONTAINER) {
  const envText = execFileSync(
    'docker',
    ['inspect', '-f', '{{range .Config.Env}}{{println .}}{{end}}', container],
    { encoding: 'utf8' },
  );
  const env = {};
  for (const line of envText.split('\n')) {
    const index = line.indexOf('=');
    if (index > 0) {
      env[line.slice(0, index)] = line.slice(index + 1);
    }
  }
  if (!env.POSTGRES_USER || !env.POSTGRES_PASSWORD || !env.POSTGRES_DB) {
    throw new Error(`Missing Postgres env on ${container}`);
  }
  const user = encodeURIComponent(env.POSTGRES_USER);
  const password = encodeURIComponent(env.POSTGRES_PASSWORD);
  const database = encodeURIComponent(env.POSTGRES_DB);
  return `postgresql://${user}:${password}@127.0.0.1:25432/${database}`;
}

async function fetchBuffer(url) {
  const response = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!response.ok) {
    throw new Error(`${response.status} ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function catalogJpegFromTcgplayerPhoto(raw) {
  const body = await sharp(raw, { failOn: 'none' })
    .rotate()
    .resize(CATALOG_WIDTH, CATALOG_HEIGHT, {
      fit: 'cover',
      position: 'centre',
      kernel: 'lanczos3',
    })
    .flatten({ background: { r: 11, g: 11, b: 15 } })
    .jpeg({ quality: 92, mozjpeg: true })
    .toBuffer();
  return {
    body,
    width: CATALOG_WIDTH,
    height: CATALOG_HEIGHT,
    sanitized: true,
  };
}

async function catalogPreviewJpeg(fullJpeg) {
  return sharp(fullJpeg, { failOn: 'none' })
    .rotate()
    .resize({ width: 180, height: 251, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85, mozjpeg: true })
    .toBuffer();
}

async function catalogHomepageWebp(fullJpeg) {
  return sharp(fullJpeg, { failOn: 'none' })
    .rotate()
    .resize({ width: HOMEPAGE_WIDTH, withoutEnlargement: true })
    .webp({ quality: HOMEPAGE_QUALITY })
    .toBuffer();
}

function writeFile(dir, key, body) {
  if (!dir || !key || !body) {
    return;
  }
  const dest = path.join(dir, key);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, body);
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

function rsyncDir(src, dest) {
  execFileSync('rsync', ['-a', '--info=stats1', `${src}/`, dest], { stdio: 'inherit' });
}

async function updateImageUrls(pool, row, updates) {
  const id = Number(row.id);
  await pool.query(
    `
      update public.pokoin_pokemon_blueprints
      set
        image_url = coalesce($1, image_url),
        cdn_image_url = coalesce($2, cdn_image_url),
        cdn_object_key = coalesce($3, cdn_object_key),
        preview_image_url = coalesce($4, preview_image_url),
        preview_object_key = coalesce($5, preview_object_key),
        homepage_image_url = coalesce($6, homepage_image_url),
        homepage_object_key = coalesce($7, homepage_object_key)
      where id = $8
        and expansion_id = $9
    `,
    [
      updates.image_url,
      updates.cdn_image_url,
      updates.cdn_object_key,
      updates.preview_image_url,
      updates.preview_object_key,
      updates.homepage_image_url,
      updates.homepage_object_key,
      id,
      LISTED_BASE_SET_EXPANSION_ID,
    ],
  );
  const params = [
    updates.image_url,
    updates.cdn_image_url,
    updates.preview_image_url,
    updates.homepage_image_url,
    id,
  ];
  for (const table of ['marketplace_cards', 'marketplace_card_versions', 'marketplace_search_candidates']) {
    await pool.query(
      `
        update public.${table}
        set
          image_url = coalesce($1, image_url),
          cdn_image_url = coalesce($2, cdn_image_url),
          preview_image_url = coalesce($3, preview_image_url),
          homepage_image_url = coalesce($4, homepage_image_url),
          projected_at = now()
        where ct_id = $5
      `,
      params,
    );
  }
}

async function maybePutR2(client, bucket, key, body, contentType) {
  if (!client || !bucket || !key || !body) {
    return false;
  }
  await backupExistingObject(client, { bucket, key });
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );
  return true;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.expansionId === SHADOWLESS_EXPANSION_ID) {
    throw new Error('Refusing to reimport Base Set Shadowless');
  }
  if (options.expansionId !== LISTED_BASE_SET_EXPANSION_ID) {
    throw new Error(`Only listed Base Set expansion ${LISTED_BASE_SET_EXPANSION_ID} is supported`);
  }
  assertSanitizeAllowed(options);

  const pool = new Pool({
    connectionString: marketplaceDatabaseUrlFromDocker(),
    ssl: false,
    max: Math.max(4, options.concurrency + 1),
  });

  const env = { ...process.env, ...readEnv(path.resolve(__dirname, '../.env.local')) };
  let r2 = null;
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  if (options.apply && env.CLOUDFLARE_ACCOUNT_ID && env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY) {
    r2 = new S3Client({
      region: 'auto',
      endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      },
    });
  }

  const stats = {
    apply: options.apply,
    cards: 0,
    wrote: 0,
    skipped: 0,
    errors: 0,
    uploaded: 0,
  };
  const log = [];

  try {
    const { rows } = await pool.query(
      `
        select
          id, name, version, expansion_id, tcg_player_ids,
          image_url, cdn_image_url, cdn_object_key,
          preview_image_url, preview_object_key,
          homepage_image_url, homepage_object_key
        from public.pokoin_pokemon_blueprints
        where expansion_id = $1
          and coalesce(version, '') ~ '[0-9]{1,3}/102'
        order by id
      `,
      [LISTED_BASE_SET_EXPANSION_ID],
    );
    const wanted = new Set(options.ids);
    const jobs = rows.filter((row) => {
      if (!isListedBaseSetSingle(row)) {
        stats.skipped += 1;
        return false;
      }
      if (wanted.size && !wanted.has(Number(row.id))) {
        return false;
      }
      return true;
    });
    stats.cards = jobs.length;
    fs.mkdirSync(options.out, { recursive: true });

    await mapPool(jobs.slice(0, options.limit), options.concurrency, async (row) => {
      const productId = firstTcgplayerId(row.tcg_player_ids);
      const sourceUrl = tcgplayerUnlimitedUrl(productId, options.fit);
      const jpegKey = leftoverJpegKey(row);
      if (!productId || !sourceUrl || !jpegKey) {
        stats.skipped += 1;
        log.push({ id: row.id, name: row.name, skipped: 'missing-source-or-key' });
        return;
      }
      try {
        const raw = await fetchBuffer(sourceUrl);
        const encoded = options.sanitize
          ? await catalogJpegFromPokemontcgPng(raw, {
            sharp,
            sanitizeCardImage,
            filename: jpegKey,
          })
          : await catalogJpegFromTcgplayerPhoto(raw);
        if (!encoded.sanitized) {
          throw new Error(`sanitize skipped ${jpegKey}`);
        }
        const homepageKey = homepageKeyFor(jpegKey);
        const aliasKey = ctIdAliasKey(row.id, jpegKey);
        const previewKey = previewKeyFor(jpegKey, row.preview_object_key);
        const previewBody = await catalogPreviewJpeg(encoded.body);
        const homepageBody = await catalogHomepageWebp(encoded.body);
        const keys = [jpegKey, aliasKey].filter(Boolean);
        for (const key of keys) {
          writeFile(options.out, key, encoded.body);
          writeFile(options.out, homepageKeyFor(key), homepageBody);
        }
        writeFile(options.out, previewKey, previewBody);
        stats.wrote += 1;
        const bust = options.cacheBust;
        const imageUrl = withCacheBust(`${CDN_BASE}/${jpegKey}`, bust);
        const homepageUrl = withCacheBust(`${CDN_BASE}/${homepageKey}`, bust);
        const previewUrl = withCacheBust(`${CDN_BASE}/${previewKey}`, bust);
        const rowLog = {
          id: row.id,
          name: row.name,
          version: row.version,
          productId,
          key: jpegKey,
          out: `${encoded.width}x${encoded.height}`,
        };
        if (!options.apply) {
          log.push(rowLog);
          return;
        }
        writeLocalCdnObject(DEFAULT_LOCAL_CDN, jpegKey, encoded.body);
        writeLocalCdnObject(DEFAULT_LOCAL_CDN, homepageKey, homepageBody);
        writeLocalCdnObject(DEFAULT_LOCAL_CDN, previewKey, previewBody);
        if (aliasKey) {
          writeLocalCdnObject(DEFAULT_LOCAL_CDN, aliasKey, encoded.body);
          writeLocalCdnObject(DEFAULT_LOCAL_CDN, homepageKeyFor(aliasKey), homepageBody);
        }
        if (r2) {
          await maybePutR2(r2, bucket, jpegKey, encoded.body, 'image/jpeg');
          await maybePutR2(r2, bucket, homepageKey, homepageBody, 'image/webp');
          await maybePutR2(r2, bucket, previewKey, previewBody, 'image/jpeg');
          if (aliasKey) {
            await maybePutR2(r2, bucket, aliasKey, encoded.body, 'image/jpeg');
            await maybePutR2(r2, bucket, homepageKeyFor(aliasKey), homepageBody, 'image/webp');
          }
        }
        await updateImageUrls(pool, row, {
          image_url: imageUrl,
          cdn_image_url: imageUrl,
          cdn_object_key: jpegKey,
          preview_image_url: previewUrl,
          preview_object_key: previewKey,
          homepage_image_url: homepageUrl,
          homepage_object_key: homepageKey,
        });
        stats.uploaded += 1;
        log.push({ ...rowLog, uploaded: true });
        if (stats.wrote === 1 || stats.wrote % 10 === 0) {
          console.log(JSON.stringify({ heartbeat: true, wrote: stats.wrote, errors: stats.errors }));
        }
      } catch (error) {
        stats.errors += 1;
        log.push({ id: row.id, name: row.name, error: String(error.message || error) });
      }
    });

    if (options.apply && options.push && stats.wrote) {
      rsyncDir(options.out, `${PI_HOST}:${PI_OBJECTS}/`);
      if (fs.existsSync(REPLICA_OBJECTS)) {
        rsyncDir(options.out, `${REPLICA_OBJECTS}/`);
      }
    }
  } finally {
    await pool.end();
  }

  const reportPath = path.join(options.out, 'base-set-unlimited.json');
  fs.mkdirSync(options.out, { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify({ ...stats, report: reportPath, log }, null, 2)}\n`);
  console.log(JSON.stringify({ ...stats, report: reportPath, sample: log.slice(0, 12) }, null, 2));
  if (stats.errors) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = {
  LISTED_BASE_SET_EXPANSION_ID,
  SHADOWLESS_EXPANSION_ID,
  TCGPLAYER_FIT,
  parseArgs,
  assertSanitizeAllowed,
  isListedBaseSetSingle,
  firstTcgplayerId,
  tcgplayerUnlimitedUrl,
  leftoverJpegKey,
  catalogJpegFromTcgplayerPhoto,
  CATALOG_WIDTH,
  CATALOG_HEIGHT,
  homepageKeyFor,
  ctIdAliasKey,
  previewKeyFor,
  withCacheBust,
  CATALOG_JPEG_QUALITY,
};
