#!/usr/bin/env node

/**
 * Scan Tag Team / Full-Art / GX Ultra catalog JPEGs for Gengar-class grey
 * die-cut ears (silver rim flattened into the dark JPEG matte). Confirm
 * against images.pokemontcg.io hires, then optionally re-encode only
 * confirmed hits.
 *
 * Reads leftover JPEGs from the local CDN mirror (exact R2 key copy).
 * Does not download catalog JPEGs. Official hires PNGs are fetched only
 * for smear hits. --apply writes R2 and the same leftover key locally.
 *
 * Storage key is the leftover {ct_id}_ key from the live URL. Never run
 * leftoverCdnObjectKey on a key that already starts with ct_id (even ids
 * would halve — 129834 → 64917).
 *
 *   node scripts/scan-suspicious-grey-corners.js
 *   node scripts/scan-suspicious-grey-corners.js --apply --cache-bust=fa2
 *   node scripts/scan-suspicious-grey-corners.js --limit=20 --concurrency=4
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, GetObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const sharp = require('sharp');
const { backupExistingObject } = require('./lib/backup-r2-original');
const { detectGreyCornerSmear } = require('./lib/grey-corner-smear');
const {
  indexPokemontcgSets,
  loadPokemontcgSets,
  matchPokemontcgSet,
} = require('./lib/pokemontcg-sets');
const {
  catalogJpegFromPokemontcgPng,
  collectorNumberFromVersion,
  hiresPngUrl,
} = require('./lib/pokemontcg-hires');
const { sanitizeCardImage } = require('./lib/sanitize-card-image');
const {
  catalogPreviewJpeg,
  isJapaneseExpansion,
  leftoverKeyFromImageUrl,
  marketplaceDatabaseUrl,
  previewObjectKey,
  readEnv,
  updateMarketplaceImageUrls,
} = require('./import-pokemontcg-expansion-hires');
const {
  DEFAULT_LOCAL_CDN,
  findExactLocal,
  writeLocalCdnObject,
} = require('./lib/local-cdn');

const DEFAULT_OUT = '/tmp/suspicious-grey-corners';
const UA = 'Pokoin grey-corner smear scan';
const CANDIDATE_SQL = `
  select distinct on (ct_id)
    card_id,
    ct_id,
    name,
    set_name,
    card_number,
    image_url
  from marketplace_cards
  where image_url ilike '%cdn.pokoin.com%'
    and image_url not ilike '%/previews/%'
    and (
      name ilike '%tag team%'
      or image_url ilike '%tag-team%'
      or card_number ilike '%full-art%'
      or card_number ilike '%full art%'
      or image_url ilike '%full-art%'
      or (
        name ~* ' GX'
        and (
          card_number ilike '%ultra%'
          or card_number ilike '%secret%'
          or card_number ilike '%full%'
        )
      )
    )
  order by ct_id, card_id
`;

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: Infinity,
    out: DEFAULT_OUT,
    concurrency: 8,
    cacheBust: 'fa2',
    localCdn: DEFAULT_LOCAL_CDN,
    localRoots: [
      DEFAULT_LOCAL_CDN,
      '/tmp/pokemontcg-expansion-jpg',
      '/home/nez/pokoincdn/cdn_images_digest/2026-08-30',
    ],
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, Number(arg.slice('--limit='.length)) || 1);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length) || DEFAULT_OUT;
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, Math.min(16, Number(arg.slice('--concurrency='.length)) || 8));
    } else if (arg.startsWith('--cache-bust=')) {
      options.cacheBust = arg.slice('--cache-bust='.length).replace(/[^a-zA-Z0-9._-]/g, '') || 'fa2';
    } else if (arg.startsWith('--local-cdn=')) {
      options.localCdn = arg.slice('--local-cdn='.length) || DEFAULT_LOCAL_CDN;
    }
  }
  return options;
}

function slimCorners(corners) {
  const out = {};
  for (const [name, value] of Object.entries(corners || {})) {
    out[name] = {
      smear: Boolean(value.smear),
      greyRun: value.greyRun,
      firstOpaque: value.firstOpaque,
    };
  }
  return out;
}

function slimRow(row) {
  const copy = { ...row, corners: slimCorners(row.corners) };
  delete copy.image_url;
  return copy;
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

async function fetchBuffer(url) {
  const response = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!response.ok) {
    const error = new Error(`${response.status} ${url}`);
    error.status = response.status;
    throw error;
  }
  return Buffer.from(await response.arrayBuffer());
}

function writeProgress(outDir, obj) {
  const line = `${JSON.stringify(obj)}\n`;
  process.stdout.write(line);
  fs.mkdirSync(outDir, { recursive: true });
  fs.appendFileSync(path.join(outDir, 'progress.jsonl'), line);
}

function loadEnv() {
  const fileEnv = readEnv(path.resolve(__dirname, '../.env.local'));
  return { ...process.env, ...fileEnv };
}

async function streamToBuffer(body) {
  if (!body) {
    return Buffer.alloc(0);
  }
  if (Buffer.isBuffer(body)) {
    return body;
  }
  if (typeof body.transformToByteArray === 'function') {
    return Buffer.from(await body.transformToByteArray());
  }
  const chunks = [];
  for await (const chunk of body) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function r2Client(env) {
  if (!env.CLOUDFLARE_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
    return null;
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

async function ensureExactLocal(client, { bucket, key, localCdn, roots }) {
  const existing = findExactLocal(roots, key);
  if (existing) {
    return existing;
  }
  if (!client || !key) {
    return null;
  }
  try {
    const out = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const body = await streamToBuffer(out.Body);
    writeLocalCdnObject(localCdn, key, body);
    return { path: path.join(localCdn, key), matched: key, how: 'r2', root: localCdn };
  } catch (error) {
    const status = error?.$metadata?.httpStatusCode;
    if (status === 404 || error?.name === 'NoSuchKey' || error?.Code === 'NoSuchKey') {
      return null;
    }
    throw error;
  }
}

async function confirmOfficial(card, live, setIndex) {
  if (isJapaneseExpansion(card.set_name)) {
    return { ok: false, reason: 'jp-expansion' };
  }
  const matched = matchPokemontcgSet(card.set_name, setIndex);
  const number = collectorNumberFromVersion(card.card_number);
  const url = matched.setId ? hiresPngUrl(matched.setId, number) : null;
  if (!url) {
    return { ok: false, reason: matched.reason || 'unmapped', setId: matched.setId, number };
  }
  let png;
  try {
    png = await fetchBuffer(url);
  } catch (error) {
    return {
      ok: false,
      reason: error.status === 404 ? 'hires-404' : `hires-${error.status || 'fetch'}`,
      setId: matched.setId,
      number,
      url,
    };
  }
  const official = await detectGreyCornerSmear(png, { sharp });
  if (official.smeared) {
    return {
      ok: false,
      reason: 'official-also-grey',
      setId: matched.setId,
      number,
      url,
      officialSmearCount: official.smearCount,
    };
  }
  return {
    ok: true,
    reason: 'confirmed',
    setId: matched.setId,
    number,
    url,
    liveSmearCount: live.smearCount,
    officialSmearCount: official.smearCount,
    png,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const env = loadEnv();
  fs.mkdirSync(options.out, { recursive: true });
  if (options.localCdn && !options.localRoots.includes(options.localCdn)) {
    options.localRoots.unshift(options.localCdn);
  }
  const stats = {
    candidates: 0,
    scanned: 0,
    smeared: 0,
    confirmed: 0,
    uploaded: 0,
    skipped: 0,
    missingLocal: 0,
    syncedFromR2: 0,
    errors: 0,
    apply: options.apply,
    localCdn: options.localCdn,
  };
  const log = [];
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const client = r2Client(env);
  if (!client) {
    throw new Error('Missing R2 credentials (needed to keep the local CDN copy exact)');
  }

  const pool = new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    ssl: { rejectUnauthorized: false },
    max: Math.max(4, Math.min(8, options.concurrency)),
  });

  try {
    const { rows } = await pool.query(CANDIDATE_SQL);
    const cards = Number.isFinite(options.limit) ? rows.slice(0, options.limit) : rows;
    stats.candidates = cards.length;
    const setIndex = indexPokemontcgSets(await loadPokemontcgSets());
    const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
    const encode = new Map();

    await mapPool(cards, options.concurrency, async (card) => {
      const row = {
        card_id: card.card_id,
        ct_id: card.ct_id,
        name: card.name,
        set: card.set_name,
        number: card.card_number,
      };
      try {
        const key = leftoverKeyFromImageUrl(card.image_url, String(card.ct_id));
        if (!key || key.startsWith('previews/')) {
          stats.errors += 1;
          row.action = 'bad-key';
          row.key = key;
          log.push(slimRow(row));
          return;
        }
        const local = await ensureExactLocal(client, {
          bucket,
          key,
          localCdn: options.localCdn,
          roots: options.localRoots,
        });
        if (!local) {
          stats.missingLocal += 1;
          row.action = 'missing-local';
          row.key = key;
          log.push(slimRow(row));
          return;
        }
        if (local.how === 'r2') {
          stats.syncedFromR2 += 1;
        }
        row.key = key;
        row.localHow = local.how;
        const jpeg = fs.readFileSync(local.path);
        const live = await detectGreyCornerSmear(jpeg, { sharp });
        stats.scanned += 1;
        row.liveSmearCount = live.smearCount;
        row.corners = live.corners;
        if (!live.smeared) {
          stats.skipped += 1;
          row.action = 'clean';
          return;
        }
        stats.smeared += 1;
        const confirmed = await confirmOfficial(card, live, setIndex);
        row.setId = confirmed.setId;
        row.hiresNumber = confirmed.number;
        row.hires = confirmed.url;
        row.confirm = confirmed.reason;
        if (!confirmed.ok) {
          stats.skipped += 1;
          row.action = 'unconfirmed';
          log.push(slimRow(row));
          return;
        }
        stats.confirmed += 1;
        row.action = options.apply ? 'upload' : 'would-encode';
        if (!options.apply) {
          log.push(slimRow(row));
          return;
        }
        const sharedKey = `${confirmed.setId}-${confirmed.number}`;
        if (!encode.has(sharedKey)) {
          encode.set(
            sharedKey,
            catalogJpegFromPokemontcgPng(confirmed.png, {
              sharp,
              sanitizeCardImage,
              filename: key,
            }),
          );
        }
        const encoded = await encode.get(sharedKey);
        const previewKey = previewObjectKey({ ct_id: card.ct_id, name: card.name });
        const previewBody = await catalogPreviewJpeg(encoded.body);
        await backupExistingObject(client, { bucket, key, env });
        await client.send(
          new PutObjectCommand({
            Bucket: bucket,
            Key: key,
            Body: encoded.body,
            ContentType: 'image/jpeg',
            CacheControl: 'public, max-age=31536000, immutable',
          }),
        );
        await backupExistingObject(client, { bucket, key: previewKey, env });
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
        await updateMarketplaceImageUrls(pool, card.ct_id, {
          image_url: url,
          cdn_image_url: url,
          cdn_object_key: key,
          preview_image_url: `${cdnBase}/${previewKey}${bust}`,
          preview_object_key: previewKey,
        });
        writeLocalCdnObject(options.localCdn, key, encoded.body);
        writeLocalCdnObject(options.localCdn, previewKey, previewBody);
        stats.uploaded += 1;
        row.uploaded = true;
        row.url = url;
        log.push(slimRow(row));
        if (stats.uploaded === 1 || stats.uploaded % 10 === 0) {
          writeProgress(options.out, {
            heartbeat: true,
            uploaded: stats.uploaded,
            confirmed: stats.confirmed,
            smeared: stats.smeared,
            scanned: stats.scanned,
          });
        }
      } catch (error) {
        stats.errors += 1;
        row.action = 'error';
        row.error = String(error.message || error);
        log.push(slimRow(row));
      }
    });
  } finally {
    await pool.end();
  }

  const smeared = log.filter((row) => row.liveSmearCount > 0);
  const confirmed = log.filter((row) => row.confirm === 'confirmed');
  const report = {
    ...stats,
    smeared,
    confirmed,
    unconfirmed: log.filter((row) => row.action === 'unconfirmed'),
    missingLocalSample: log.filter((row) => row.action === 'missing-local').slice(0, 40),
    errorRows: log.filter((row) => row.action === 'error').slice(0, 40),
  };
  const reportPath = path.join(options.out, 'suspicious-grey-corners.json');
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  console.log(
    JSON.stringify(
      {
        ...stats,
        report: reportPath,
        smearedSets: [...new Set(smeared.map((row) => row.set))],
        confirmedSets: [...new Set(confirmed.map((row) => row.set))],
        sample: confirmed.slice(0, 12).map((row) => ({
          name: row.name,
          set: row.set,
          key: row.key,
          smear: row.liveSmearCount,
        })),
      },
      null,
      2,
    ),
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { parseArgs, CANDIDATE_SQL, slimCorners };
