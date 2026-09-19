#!/usr/bin/env node
'use strict';

/**
 * Convert PNG-only R2 objects to max-quality JPEG.
 * Copies each PNG to originals/{key} once, PutObject sibling .jpg, then
 * deletes the live PNG. Skips originals/ and manifests/. JPEG is still
 * DCT-lossy (q100 / 4:4:4).
 */

const fs = require('node:fs');
const path = require('node:path');
const {
  DeleteObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');
const { backupExistingObject } = require('./lib/backup-r2-original');
const { pngToMaxJpeg, siblingJpegKey } = require('./lib/png-to-jpeg');

const DEFAULT_LOG = '/home/nez/pokoincdn/cdn_images_digest/2026-08-30-png/convert-png-only.log.jsonl';
const DEFAULT_LOCAL_CDN = '/home/nez/Projects/pokoin/PokoinTest/index/cdn_images';

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

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: 0,
    concurrency: 6,
    only: [],
    errorLimit: 40,
    logPath: DEFAULT_LOG,
    localCdn: DEFAULT_LOCAL_CDN,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--limit') {
      options.limit = Number(argv[i + 1] || 0);
      i += 1;
    } else if (arg === '--concurrency') {
      options.concurrency = Number(argv[i + 1] || 6);
      i += 1;
    } else if (arg === '--only') {
      options.only = String(argv[i + 1] || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      i += 1;
    } else if (arg === '--error-limit') {
      options.errorLimit = Number(argv[i + 1] || 40);
      i += 1;
    } else if (arg === '--local-cdn') {
      options.localCdn = String(argv[i + 1] || '').trim();
      i += 1;
    } else if (arg === '--log') {
      options.logPath = String(argv[i + 1] || '').trim();
      i += 1;
    }
  }
  return options;
}

function skipKey(key) {
  return key.startsWith('originals/') || key.startsWith('manifests/');
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

async function getObjectBuffer(client, bucket, key) {
  const out = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  return Buffer.from(await out.Body.transformToByteArray());
}

function readLocalPng(localCdn, key) {
  if (!localCdn) {
    return null;
  }
  const dest = path.join(localCdn, key);
  if (!dest.startsWith(path.resolve(localCdn) + path.sep) && dest !== path.resolve(localCdn)) {
    return null;
  }
  if (!fs.existsSync(dest)) {
    return null;
  }
  return fs.readFileSync(dest);
}

async function loadPng({ client, bucket, key, localCdn }) {
  const local = readLocalPng(localCdn, key);
  if (local) {
    return { body: local, source: 'local' };
  }
  return { body: await getObjectBuffer(client, bucket, key), source: 'r2' };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const env = { ...readEnv(path.resolve(__dirname, '../.env.local')), ...process.env };
  if (!env.CLOUDFLARE_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
    throw new Error('Missing R2 credentials');
  }
  const sharp = require('sharp');
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  const keys = new Map();
  let token;
  do {
    const out = await client.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        ContinuationToken: token,
        MaxKeys: 1000,
      }),
    );
    for (const obj of out.Contents || []) {
      keys.set(obj.Key, obj.Size || 0);
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token);

  const rasterExts = ['.jpg', '.jpeg', '.webp'];
  let pngOnly = [...keys.keys()].filter((key) => {
    if (!/\.png$/i.test(key) || skipKey(key)) {
      return false;
    }
    const stem = key.replace(/\.[^.]+$/, '');
    return !rasterExts.some((ext) => keys.has(`${stem}${ext}`));
  });
  if (options.only.length > 0) {
    const wanted = new Set(options.only);
    pngOnly = pngOnly.filter((key) => wanted.has(key));
  }
  pngOnly.sort();
  if (options.limit > 0) {
    pngOnly = pngOnly.slice(0, options.limit);
  }

  fs.mkdirSync(path.dirname(options.logPath), { recursive: true });
  const summary = {
    apply: options.apply,
    total: pngOnly.length,
    ok: 0,
    skipped: 0,
    failed: 0,
    jpegBytes: 0,
    pngBytes: 0,
  };
  console.log(
    JSON.stringify({
      start: true,
      ...summary,
      concurrency: options.concurrency,
      localCdn: options.localCdn || env.ORACLE_IMAGE_LOCAL_CDN || DEFAULT_LOCAL_CDN,
    }),
  );

  await mapLimit(pngOnly, options.concurrency, async (pngKey, index) => {
    const jpegKey = siblingJpegKey(pngKey);
    try {
      if (!jpegKey) {
        summary.skipped += 1;
        return { pngKey, status: 'skipped' };
      }
      const loaded = await loadPng({
        client,
        bucket,
        key: pngKey,
        localCdn: options.localCdn || env.ORACLE_IMAGE_LOCAL_CDN || DEFAULT_LOCAL_CDN,
      });
      const source = loaded.body;
      const converted = await pngToMaxJpeg(source, { sharp });
      if (!options.apply) {
        summary.ok += 1;
        fs.appendFileSync(
          options.logPath,
          `${JSON.stringify({
            status: 'dry-run',
            pngKey,
            jpegKey,
            pngBytes: source.length,
            jpegBytes: converted.body.length,
            hadAlpha: converted.hadAlpha,
            source: loaded.source,
            index,
          })}\n`,
        );
        if ((index + 1) % 25 === 0 || index === 0) {
          console.log(JSON.stringify({ progress: index + 1, ...summary, last: pngKey }));
        }
        return { pngKey, status: 'dry-run' };
      }
      const backup = await backupExistingObject(client, { bucket, key: pngKey });
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: jpegKey,
          Body: converted.body,
          ContentType: 'image/jpeg',
          CacheControl: 'public, max-age=31536000, immutable',
        }),
      );
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: pngKey }));
      summary.ok += 1;
      summary.jpegBytes += converted.body.length;
      summary.pngBytes += source.length;
      const record = {
        status: 'ok',
        pngKey,
        jpegKey,
        key: jpegKey,
        backup: backup.reason || (backup.backedUp ? 'copied' : 'none'),
        pngBytes: source.length,
        jpegBytes: converted.body.length,
        hadAlpha: converted.hadAlpha,
        source: loaded.source,
        index,
      };
      fs.appendFileSync(options.logPath, `${JSON.stringify(record)}\n`);
      if ((index + 1) % 25 === 0 || index === 0) {
        console.log(JSON.stringify({ progress: index + 1, ...summary, last: pngKey }));
      }
      return record;
    } catch (error) {
      summary.failed += 1;
      const record = { status: 'failed', pngKey, jpegKey, error: error.message, index };
      fs.appendFileSync(options.logPath, `${JSON.stringify(record)}\n`);
      console.error(JSON.stringify(record));
      if (summary.failed >= options.errorLimit) {
        throw new Error(`stopping after ${summary.failed} errors`);
      }
      return record;
    }
  });

  console.log(JSON.stringify({ summary, logPath: options.logPath }));
  if (!options.apply) {
    console.log('dry-run only; pass --apply to backup PNG, PutObject JPEG, and delete PNG');
  }
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

module.exports = { parseArgs, siblingJpegKey, skipKey };

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
