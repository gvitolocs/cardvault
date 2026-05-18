const fs = require('fs');
const { S3Client, ListObjectsV2Command } = require('@aws-sdk/client-s3');

function readEnv(path) {
  const values = {};
  for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return { ...values, ...process.env };
}

async function listKeysByBlueprintId(env, bucket) {
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  const matches = new Map();
  let continuationToken;
  do {
    const response = await client.send(new ListObjectsV2Command({
      Bucket: bucket,
      ContinuationToken: continuationToken,
      MaxKeys: 1000,
    }));
    for (const object of response.Contents || []) {
      const key = object.Key || '';
      const prefix = key.split('_', 1)[0];
      if (/^\d+$/.test(prefix)) {
        matches.set(Number(prefix), key);
      }
    }
    continuationToken = response.NextContinuationToken;
  } while (continuationToken);
  return matches;
}

function sqlString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

async function updateBatch(env, rows) {
  const values = rows
    .map((row) => `(${row.id},${sqlString(row.image_url)},${sqlString(row.cdn_object_key)})`)
    .join(',');
  const query = `
update public.cardtrader_pokemon_blueprints as b
set
  image_url = v.image_url,
  cdn_image_url = v.image_url,
  cdn_object_key = v.cdn_object_key
from (values ${values}) as v(id, image_url, cdn_object_key)
where b.id = v.id::bigint;
`;
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.SUPABASE_SECRET_ACCESS_TOKEN || env.SUPABASE_SECRET_ACCESS_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase update failed ${response.status}: ${await response.text()}`);
  }
}

async function existingBlueprintIds(env, ids) {
  const response = await fetch(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_blueprints?select=id&id=in.(${ids.join(',')})`,
    {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase id lookup failed ${response.status}: ${await response.text()}`);
  }
  return new Set((await response.json()).map((row) => row.id));
}

async function main() {
  const env = readEnv('.env.local');
  const bucket =
    env.POKOIN_CARD_IMAGES_BUCKET ||
    'cardvault-images';
  const cdnBase = (
    env.POKOIN_CARD_CDN_BASE_URL ||
    'https://cdn.pokoin.com'
  ).replace(/\/$/, '');

  const keysById = await listKeysByBlueprintId(env, bucket);
  console.log(`matched CDN object keys by id: ${keysById.size}`);

  let batch = [];
  let updated = 0;
  for (const [id, key] of [...keysById.entries()].sort((a, b) => a[0] - b[0])) {
    const cdnUrl = `${cdnBase}/${key}`;
    batch.push({
      id,
      image_url: cdnUrl,
      cdn_image_url: cdnUrl,
      cdn_object_key: key,
    });
    if (batch.length >= 500) {
      const allowedIds = await existingBlueprintIds(env, batch.map((row) => row.id));
      const existingRows = batch.filter((row) => allowedIds.has(row.id));
      if (existingRows.length > 0) {
        await updateBatch(env, existingRows);
      }
      updated += existingRows.length;
      console.log(`updated ${updated}`);
      batch = [];
    }
  }
  if (batch.length > 0) {
    const allowedIds = await existingBlueprintIds(env, batch.map((row) => row.id));
    const existingRows = batch.filter((row) => allowedIds.has(row.id));
    if (existingRows.length > 0) {
      await updateBatch(env, existingRows);
    }
    updated += existingRows.length;
    console.log(`updated ${updated}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
