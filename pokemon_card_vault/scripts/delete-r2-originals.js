#!/usr/bin/env node
'use strict';

/**
 * Delete R2 `originals/` backups only. Live leftover catalog keys stay.
 *
 *   node scripts/delete-r2-originals.js
 *   node scripts/delete-r2-originals.js --apply
 */

const fs = require('node:fs');
const path = require('node:path');
const { DeleteObjectsCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');

function readEnv(filePath) {
  const values = {};
  if (!fs.existsSync(filePath)) return values;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    values[key] = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
  }
  return values;
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

  const keys = [];
  let bytes = 0;
  let token;
  do {
    const res = await client.send(new ListObjectsV2Command({
      Bucket: bucket,
      Prefix: 'originals/',
      ContinuationToken: token,
      MaxKeys: 1000,
    }));
    for (const obj of res.Contents || []) {
      if (!obj.Key || obj.Key === 'originals/' || !obj.Key.startsWith('originals/')) continue;
      keys.push(obj.Key);
      bytes += Number(obj.Size || 0);
    }
    token = res.IsTruncated ? res.NextContinuationToken : undefined;
  } while (token);

  const summary = {
    bucket,
    apply,
    files: keys.length,
    gb: +(bytes / 1e9).toFixed(2),
    deleted: 0,
    errors: 0,
  };
  if (!apply) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  for (let i = 0; i < keys.length; i += 1000) {
    const chunk = keys.slice(i, i + 1000);
    const res = await client.send(new DeleteObjectsCommand({
      Bucket: bucket,
      Delete: {
        Quiet: true,
        Objects: chunk.map((Key) => ({ Key })),
      },
    }));
    const errCount = (res.Errors || []).length;
    summary.errors += errCount;
    summary.deleted += chunk.length - errCount;
    if (errCount) {
      console.error(`batch ${i}: ${errCount} errors`);
    }
  }
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
