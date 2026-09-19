#!/usr/bin/env node
'use strict';

/**
 * Download R2 PNG-only objects that are missing from the local CDN copy.
 * Does not overwrite existing local files. Does not delete R2 objects.
 */

const fs = require('node:fs');
const path = require('node:path');
const { GetObjectCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');

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
  const options = { apply: false, concurrency: 24, localCdn: DEFAULT_LOCAL_CDN };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--concurrency') {
      options.concurrency = Number(argv[i + 1] || 24);
      i += 1;
    } else if (arg === '--local-cdn') {
      options.localCdn = String(argv[i + 1] || '').trim();
      i += 1;
    }
  }
  return options;
}

function skipKey(key) {
  return key.startsWith('originals/') || key.startsWith('manifests/');
}

function localPathFor(root, key) {
  const dest = path.resolve(root, key);
  const base = path.resolve(root);
  if (dest !== base && !dest.startsWith(`${base}${path.sep}`)) {
    throw new Error(`refusing path ${key}`);
  }
  return dest;
}

async function mapLimit(items, concurrency, fn) {
  let next = 0;
  const n = Math.max(1, Math.min(concurrency, items.length || 1));
  async function worker() {
    while (true) {
      const index = next;
      next += 1;
      if (index >= items.length) {
        return;
      }
      await fn(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: n }, () => worker()));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const env = { ...readEnv(path.resolve(__dirname, '../.env.local')), ...process.env };
  if (!env.CLOUDFLARE_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
    throw new Error('Missing R2 credentials');
  }
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
  const pngOnly = [...keys.entries()].filter(([key]) => {
    if (!/\.png$/i.test(key) || skipKey(key)) {
      return false;
    }
    const stem = key.replace(/\.[^.]+$/, '');
    return !rasterExts.some((ext) => keys.has(`${stem}${ext}`));
  });

  const missing = [];
  let present = 0;
  for (const [key, size] of pngOnly) {
    const dest = localPathFor(options.localCdn, key);
    if (fs.existsSync(dest)) {
      present += 1;
      continue;
    }
    missing.push({ key, size, dest });
  }

  const bytes = missing.reduce((sum, row) => sum + row.size, 0);
  console.log(
    JSON.stringify({
      apply: options.apply,
      pngOnly: pngOnly.length,
      alreadyLocal: present,
      missing: missing.length,
      missingMiB: Math.round(bytes / 1024 / 1024),
      concurrency: options.concurrency,
      localCdn: options.localCdn,
    }),
  );

  if (!options.apply) {
    console.log('dry-run only; pass --apply to download missing PNGs');
    return;
  }

  const summary = { ok: 0, failed: 0, bytes: 0 };
  await mapLimit(missing, options.concurrency, async (row, index) => {
    try {
      const out = await client.send(new GetObjectCommand({ Bucket: bucket, Key: row.key }));
      const body = Buffer.from(await out.Body.transformToByteArray());
      fs.mkdirSync(path.dirname(row.dest), { recursive: true });
      fs.writeFileSync(row.dest, body);
      summary.ok += 1;
      summary.bytes += body.length;
      if ((index + 1) % 50 === 0 || index === 0) {
        console.log(JSON.stringify({ progress: index + 1, ...summary, last: row.key }));
      }
    } catch (error) {
      summary.failed += 1;
      console.error(JSON.stringify({ key: row.key, status: 'failed', error: error.message }));
    }
  });
  console.log(JSON.stringify({ summary }));
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
