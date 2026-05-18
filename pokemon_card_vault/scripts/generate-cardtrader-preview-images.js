const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');

function readEnv(filePath) {
  const values = {};
  if (!fs.existsSync(filePath)) {
    return { ...process.env };
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
  return { ...values, ...process.env };
}

function required(env, key) {
  if (!env[key]) {
    throw new Error(`Missing ${key}`);
  }
  return env[key];
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function fetchRows(env, limit, offset) {
  const url = new URL(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_blueprints`,
  );
  url.searchParams.set(
    'select',
    'id,name,cdn_object_key,cdn_image_url,preview_image_url',
  );
  url.searchParams.set('cdn_object_key', 'not.is.null');
  url.searchParams.set('order', 'id.asc');
  url.searchParams.set('limit', String(limit));
  url.searchParams.set('offset', String(offset));

  const response = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });
  if (!response.ok) {
    throw new Error(`Supabase fetch failed ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function updateRows(env, rows) {
  for (const row of rows) {
    const response = await fetch(
      `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_blueprints?id=eq.${row.id}`,
      {
        method: 'PATCH',
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({
          preview_image_url: row.preview_image_url,
          preview_object_key: row.preview_object_key,
        }),
      },
    );
    if (!response.ok) {
      throw new Error(`Supabase preview update failed ${response.status}: ${await response.text()}`);
    }
  }
}

async function updateRowsViaSql(env, rows) {
  if (rows.length === 0) {
    return;
  }
  const values = rows
    .map((row) => {
      const url = String(row.preview_image_url).replace(/'/g, "''");
      const key = String(row.preview_object_key).replace(/'/g, "''");
      return `(${row.id},'${url}','${key}')`;
    })
    .join(',');
  const query = `
update public.cardtrader_pokemon_blueprints as b
set
  preview_image_url = v.preview_image_url,
  preview_object_key = v.preview_object_key
from (values ${values}) as v(id, preview_image_url, preview_object_key)
where b.id = v.id::bigint;
`;
  const token = env.SUPABASE_SECRET_ACCESS_TOKEN || env.SUPABASE_SECRET_ACCESS_KEY;
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase SQL update failed ${response.status}: ${await response.text()}`);
  }
}

async function main() {
  const env = readEnv(path.resolve('.env.local'));
  required(env, 'CLOUDFLARE_ACCOUNT_ID');
  required(env, 'R2_ACCESS_KEY_ID');
  required(env, 'R2_SECRET_ACCESS_KEY');
  required(env, 'SUPABASE_URL');
  required(env, 'SUPABASE_SERVICE_ROLE_KEY');

  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com')
    .replace(/\/$/, '');
  const batchSize = Number(process.env.PREVIEW_BATCH_SIZE || 100);
  const maxRows = Number(process.env.PREVIEW_MAX_ROWS || 0);
  const force = process.env.PREVIEW_FORCE === '1';
  const useSql = Boolean(
    env.SUPABASE_PROJECT_REF &&
      (env.SUPABASE_SECRET_ACCESS_TOKEN || env.SUPABASE_SECRET_ACCESS_KEY),
  );

  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  let offset = 0;
  let generated = 0;
  while (true) {
    const rows = await fetchRows(env, batchSize, offset);
    if (rows.length === 0) {
      break;
    }

    const updates = [];
    for (const row of rows) {
      if (!force && row.preview_image_url) {
        continue;
      }
      const sourceKey = row.cdn_object_key;
      const previewKey = `previews/${sourceKey.replace(/\.[^.]+$/, '')}.webp`;
      const object = await client.send(
        new GetObjectCommand({ Bucket: bucket, Key: sourceKey }),
      );
      const source = await streamToBuffer(object.Body);
      const preview = await sharp(source)
        .resize({ width: 96, height: 134, fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 72 })
        .toBuffer();
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: previewKey,
          Body: preview,
          ContentType: 'image/webp',
          CacheControl: 'public, max-age=31536000, immutable',
        }),
      );
      updates.push({
        id: row.id,
        preview_image_url: `${cdnBase}/${previewKey}`,
        preview_object_key: previewKey,
      });
      generated += 1;
    }

    if (useSql) {
      await updateRowsViaSql(env, updates);
    } else {
      await updateRows(env, updates);
    }
    console.log(`processed ${offset + rows.length}, generated ${generated}`);

    offset += rows.length;
    if (maxRows > 0 && offset >= maxRows) {
      break;
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
