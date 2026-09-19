#!/usr/bin/env node
/**
 * Mirror One Piece / Riftbound objects from R2 `cardvault-images` onto a local
 * tree. cdn.pokoin.com 404s `one-piece/previews/` and many `.webp` keys; R2 has them.
 * Keys stay exactly as stored (one-piece/..., riftbound/...). Never prints secrets.
 *
 *   node scripts/mirror-multigame-cdn.js --dest=/home/nez/mnt/mybook/datasets/tcg/pokoin-cdn --concurrency=24
 */
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
const { URL } = require('url');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');

const ROOT = path.resolve(__dirname, '..');

function loadEnv() {
  const envPath = path.join(ROOT, '.env.local');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\n/)) {
    const s = line.trim();
    if (!s || s.startsWith('#') || !s.includes('=')) continue;
    const i = s.indexOf('=');
    const k = s.slice(0, i).replace(/^export\s+/, '').trim();
    let v = s.slice(i + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    if (!process.env[k]) process.env[k] = v;
  }
}

function parseArgs(argv) {
  const options = {
    dest: '',
    concurrency: 24,
    games: ['one_piece', 'riftbound'],
  };
  for (const arg of argv) {
    if (arg.startsWith('--dest=')) options.dest = arg.slice('--dest='.length);
    else if (arg.startsWith('--concurrency=')) options.concurrency = Number(arg.slice('--concurrency='.length));
    else if (arg.startsWith('--games=')) options.games = arg.slice('--games='.length).split(',').map((s) => s.trim()).filter(Boolean);
  }
  if (!options.dest) throw new Error('--dest is required');
  if (!Number.isSafeInteger(options.concurrency) || options.concurrency < 1 || options.concurrency > 64) {
    throw new Error('--concurrency must be 1..64');
  }
  return options;
}

function withDb(name) {
  const u = new URL(process.env.MARKETPLACE_DATABASE_URL);
  u.pathname = `/${name}`;
  return u.toString();
}

const TARGETS = {
  one_piece: { db: 'pokoin_one_piece', schema: 'marketplace_one_piece' },
  riftbound: { db: 'pokoin_riftbound', schema: 'marketplace_riftbound' },
};

async function loadKeys(game) {
  const target = TARGETS[game];
  if (!target) throw new Error(`unknown game ${game}`);
  const client = new Client({
    connectionString: withDb(target.db),
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  const result = await client.query(`
    select cdn_object_key, preview_object_key, homepage_object_key
    from ${target.schema}.cardtrader_blueprints
    where cdn_object_key is not null
  `);
  await client.end();
  const keys = new Set();
  for (const row of result.rows) {
    for (const value of [row.cdn_object_key, row.preview_object_key, row.homepage_object_key]) {
      if (value && !String(value).includes('..')) keys.add(String(value).replace(/^\/+/, ''));
    }
  }
  return [...keys];
}

async function runWorkers(items, concurrency, worker) {
  let index = 0;
  async function runOne() {
    while (index < items.length) {
      const itemIndex = index;
      index += 1;
      await worker(items[itemIndex], itemIndex);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length || 1) }, () => runOne()));
}

function createR2Client() {
  if (!process.env.CLOUDFLARE_ACCOUNT_ID || !process.env.R2_ACCESS_KEY_ID || !process.env.R2_SECRET_ACCESS_KEY) {
    throw new Error('CLOUDFLARE_ACCOUNT_ID, R2_ACCESS_KEY_ID, and R2_SECRET_ACCESS_KEY are required (cdn.pokoin.com 404s one-piece/previews and many webp keys).');
  }
  return new S3Client({
    region: 'auto',
    endpoint: `https://${process.env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: process.env.R2_ACCESS_KEY_ID,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
  });
}

async function downloadKey(client, bucket, destRoot, key) {
  const dest = path.join(destRoot, key);
  if (fs.existsSync(dest) && fs.statSync(dest).size > 32) return 'skip';
  const obj = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const body = Buffer.from(await obj.Body.transformToByteArray());
  if (body.length < 32) throw new Error(`too small ${body.length} ${key}`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, body);
  return 'ok';
}

async function main() {
  loadEnv();
  if (!process.env.MARKETPLACE_DATABASE_URL) throw new Error('MARKETPLACE_DATABASE_URL is required');
  const options = parseArgs(process.argv.slice(2));
  fs.mkdirSync(options.dest, { recursive: true });
  const bucket = process.env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const client = createR2Client();
  const summary = { dest: options.dest, source: 'r2', bucket, games: {}, ok: 0, skip: 0, failed: 0, samples: [] };
  for (const game of options.games) {
    const keys = await loadKeys(game);
    const gameSummary = { keys: keys.length, ok: 0, skip: 0, failed: 0 };
    await runWorkers(keys, options.concurrency, async (key) => {
      try {
        const result = await downloadKey(client, bucket, options.dest, key);
        if (result === 'skip') {
          gameSummary.skip += 1;
          summary.skip += 1;
        } else {
          gameSummary.ok += 1;
          summary.ok += 1;
          if ((gameSummary.ok + gameSummary.skip) % 250 === 0) {
            console.error(`mirror-progress game=${game} ok=${gameSummary.ok} skip=${gameSummary.skip} failed=${gameSummary.failed} of ${keys.length}`);
          }
        }
      } catch (error) {
        gameSummary.failed += 1;
        summary.failed += 1;
        if (summary.samples.length < 15) summary.samples.push({ key, error: error.message });
      }
    });
    summary.games[game] = gameSummary;
  }
  console.log(JSON.stringify(summary, null, 2));
  if (summary.failed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
