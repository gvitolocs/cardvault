#!/usr/bin/env node
'use strict';

/**
 * Delete catalog PNG objects that already have a JPEG/WebP sibling.
 * Does not delete originals/, artist-profiles/, or expansions/.
 * Does not delete PNG-only objects (no JPEG/WebP twin) — those would 404.
 * The CDN Worker must map leftover .png URLs to those JPEG *and* WebP twins.
 */

const fs = require('node:fs');
const path = require('node:path');
const { DeleteObjectCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');

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

function stemKey(key) {
  return String(key).replace(/\.[^.]+$/, '');
}

function protectedPrefix(key) {
  return (
    key.startsWith('originals/') ||
    key.startsWith('artist-profiles/') ||
    key.startsWith('expansions/') ||
    key.startsWith('manifests/')
  );
}

async function mapLimit(items, concurrency, fn) {
  let next = 0;
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
  const n = Math.max(1, Math.min(concurrency, items.length || 1));
  await Promise.all(Array.from({ length: n }, () => worker()));
}

async function main() {
  const apply = process.argv.includes('--apply');
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
  const toDelete = [];
  const skipped = { protected: 0, pngOnly: 0, pngOnlyBytes: 0 };
  for (const [key, size] of keys) {
    if (!/\.png$/i.test(key)) {
      continue;
    }
    if (protectedPrefix(key)) {
      skipped.protected += 1;
      continue;
    }
    const stem = stemKey(key);
    const sibling = rasterExts.map((ext) => `${stem}${ext}`).find((candidate) => keys.has(candidate));
    if (!sibling) {
      skipped.pngOnly += 1;
      skipped.pngOnlyBytes += size;
      continue;
    }
    toDelete.push({ key, size, sibling });
  }

  const logPath = '/home/nez/pokoincdn/cdn_images_digest/2026-08-30-png/delete-png-siblings.log.jsonl';
  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  const bytes = toDelete.reduce((sum, row) => sum + row.size, 0);
  console.log(
    JSON.stringify({
      apply,
      candidates: toDelete.length,
      bytes,
      miB: Math.round(bytes / 1024 / 1024),
      skipped,
    }),
  );

  if (!apply) {
    console.log('dry-run only; pass --apply to DeleteObject sibling PNGs');
    return;
  }

  const summary = { deleted: 0, failed: 0, bytes: 0 };
  await mapLimit(toDelete, 8, async (row) => {
    try {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: row.key }));
      summary.deleted += 1;
      summary.bytes += row.size;
      fs.appendFileSync(logPath, `${JSON.stringify({ ...row, status: 'deleted' })}\n`);
    } catch (error) {
      summary.failed += 1;
      fs.appendFileSync(
        logPath,
        `${JSON.stringify({ key: row.key, status: 'failed', error: error.message })}\n`,
      );
      console.error(JSON.stringify({ key: row.key, status: 'failed', error: error.message }));
    }
  });
  console.log(JSON.stringify({ summary, logPath }));
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
