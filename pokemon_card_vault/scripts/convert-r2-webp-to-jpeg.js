#!/usr/bin/env node
'use strict';

/**
 * Convert live catalog WebP (and leftover PNG) to max-quality JPEG.
 * Copies each source to originals/{key} once, PutObject sibling .jpg, then
 * deletes the live WebP/PNG. Skips originals/, manifests/, previews/,
 * expansions/, artist-profiles/, and *_homepage.webp.
 */

const fs = require('node:fs');
const path = require('node:path');
const {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');
const { backupExistingObject } = require('./lib/backup-r2-original');
const { pngToMaxJpeg, siblingJpegKey } = require('./lib/png-to-jpeg');

const DEFAULT_LOG = '/home/nez/pokoincdn/cdn_images_digest/2026-08-31-jpg/convert-webp-to-jpeg.log.jsonl';

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
    concurrency: 8,
    errorLimit: 40,
    logPath: DEFAULT_LOG,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--limit') {
      options.limit = Number(argv[i + 1] || 0);
      i += 1;
    } else if (arg === '--concurrency') {
      options.concurrency = Number(argv[i + 1] || 8);
      i += 1;
    } else if (arg === '--error-limit') {
      options.errorLimit = Number(argv[i + 1] || 40);
      i += 1;
    } else if (arg === '--log') {
      options.logPath = String(argv[i + 1] || '').trim();
      i += 1;
    }
  }
  return options;
}

function skipKey(key) {
  return (
    key.startsWith('originals/') ||
    key.startsWith('manifests/') ||
    key.startsWith('previews/') ||
    key.startsWith('expansions/') ||
    key.startsWith('artist-profiles/') ||
    /_homepage\.webp$/i.test(key)
  );
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

async function headExists(client, bucket, key) {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (error) {
    const status = error?.$metadata?.httpStatusCode;
    if (
      status === 404 ||
      error?.name === 'NotFound' ||
      error?.name === 'NoSuchKey' ||
      error?.Code === 'NotFound' ||
      error?.Code === 'NoSuchKey'
    ) {
      return false;
    }
    throw error;
  }
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

  let sources = [...keys.keys()].filter((key) => {
    if (skipKey(key) || !/\.(webp|png)$/i.test(key)) {
      return false;
    }
    return Boolean(siblingJpegKey(key));
  });
  sources.sort();
  if (options.limit > 0) {
    sources = sources.slice(0, options.limit);
  }

  fs.mkdirSync(path.dirname(options.logPath), { recursive: true });
  const summary = {
    apply: options.apply,
    total: sources.length,
    converted: 0,
    alreadyJpeg: 0,
    skipped: 0,
    failed: 0,
  };
  console.log(JSON.stringify({ start: true, ...summary, concurrency: options.concurrency }));

  await mapLimit(sources, options.concurrency, async (sourceKey, index) => {
    const jpegKey = siblingJpegKey(sourceKey);
    try {
      const hasJpeg = keys.has(jpegKey) || (await headExists(client, bucket, jpegKey));
      if (hasJpeg) {
        if (!options.apply) {
          summary.alreadyJpeg += 1;
          if ((index + 1) % 500 === 0 || index === 0) {
            console.log(JSON.stringify({ progress: index + 1, ...summary, last: sourceKey }));
          }
          return { status: 'already-jpeg', sourceKey, jpegKey, index };
        }
        const backup = await backupExistingObject(client, { bucket, key: sourceKey });
        await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: sourceKey }));
        summary.alreadyJpeg += 1;
        const record = {
          status: 'deleted-duplicate',
          pngKey: sourceKey,
          jpegKey,
          key: jpegKey,
          backup: backup.reason || (backup.backedUp ? 'copied' : 'none'),
          index,
        };
        fs.appendFileSync(options.logPath, `${JSON.stringify(record)}\n`);
        return record;
      }
      if (!options.apply) {
        summary.converted += 1;
        if ((index + 1) % 500 === 0 || index === 0) {
          console.log(JSON.stringify({ progress: index + 1, ...summary, last: sourceKey }));
        }
        return { status: 'dry-run', sourceKey, jpegKey, index };
      }
      const source = await getObjectBuffer(client, bucket, sourceKey);
      const converted = await pngToMaxJpeg(source, { sharp });
      const backup = await backupExistingObject(client, { bucket, key: sourceKey });
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: jpegKey,
          Body: converted.body,
          ContentType: 'image/jpeg',
          CacheControl: 'public, max-age=31536000, immutable',
        }),
      );
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: sourceKey }));
      summary.converted += 1;
      const record = {
        status: 'ok',
        pngKey: sourceKey,
        jpegKey,
        key: jpegKey,
        backup: backup.reason || (backup.backedUp ? 'copied' : 'none'),
        sourceBytes: source.length,
        jpegBytes: converted.body.length,
        index,
      };
      fs.appendFileSync(options.logPath, `${JSON.stringify(record)}\n`);
      if ((index + 1) % 25 === 0 || index === 0) {
        console.log(JSON.stringify({ progress: index + 1, ...summary, last: sourceKey }));
      }
      return record;
    } catch (error) {
      summary.failed += 1;
      const record = { status: 'failed', pngKey: sourceKey, jpegKey, error: error.message, index };
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
    console.log('dry-run only; pass --apply to backup, PutObject JPEG, and delete WebP/PNG');
  }
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { parseArgs, skipKey };
