const fs = require('fs');
const path = require('path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');

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

function normalizeCardTraderUrl(rawValue, { allowPreview }) {
  const rawUrl = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (!rawUrl || rawUrl.includes('/fallbacks/card_uploader/')) {
    return null;
  }
  if (!allowPreview && rawUrl.includes('/preview_')) {
    return null;
  }
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
    return rawUrl;
  }
  if (rawUrl.startsWith('/')) {
    return `https://cardtrader.com${rawUrl}`;
  }
  return `https://cardtrader.com/${rawUrl}`;
}

function previewCardTraderImageUrl(row) {
  const image = row.blueprint?.image;
  const candidates = [
    typeof image?.preview?.url === 'string' ? image.preview.url : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof image?.show?.url === 'string' ? image.show.url : null,
    typeof image?.url === 'string' ? image.url : null,
  ];
  for (const candidate of candidates) {
    const normalized = normalizeCardTraderUrl(candidate, { allowPreview: true });
    if (normalized) {
      return normalized;
    }
  }
  return null;
}

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

async function fetchRows(env, { ids, limit, offset, cursorId, missingOnly, sortDirection }) {
  const url = new URL(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_blueprints`,
  );
  url.searchParams.set(
    'select',
    'id,name,preview_image_url,preview_object_key,blueprint',
  );
  if (ids.length > 0) {
    url.searchParams.set('id', `in.(${ids.join(',')})`);
  } else {
    if (missingOnly) {
      url.searchParams.set('preview_image_url', 'is.null');
    }
    if (cursorId > 0) {
      url.searchParams.set('id', sortDirection === 'desc' ? `lt.${cursorId}` : `gt.${cursorId}`);
    }
    url.searchParams.set('order', `id.${sortDirection}`);
    url.searchParams.set('limit', String(limit));
    if (cursorId === 0) {
      url.searchParams.set('offset', String(offset));
    }
  }

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

async function patchTable(env, table, id, values) {
  const response = await fetch(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/${table}?card_id=eq.${id}`,
    {
      method: 'PATCH',
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
      },
      body: JSON.stringify(values),
    },
  );
  if (!response.ok) {
    throw new Error(`${table} preview update failed ${response.status}: ${await response.text()}`);
  }
}

async function updateRow(env, row) {
  const blueprintBody = {
    preview_image_url: row.preview_image_url,
    preview_object_key: row.preview_object_key,
  };
  const projectionBody = {
    preview_image_url: row.preview_image_url,
  };
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
      body: JSON.stringify(blueprintBody),
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase update failed ${response.status}: ${await response.text()}`);
  }
  await patchTable(env, 'marketplace_cards', row.id, projectionBody);
  await patchTable(env, 'marketplace_card_versions', row.id, projectionBody);
}

async function download(sourceUrl) {
  const response = await fetch(sourceUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Pokoin preview importer)',
      Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    },
  });
  if (!response.ok) {
    throw new Error(`Preview download failed ${response.status}: ${sourceUrl}`);
  }
  const body = Buffer.from(await response.arrayBuffer());
  if (body.length < 256) {
    throw new Error(`Preview download too small (${body.length} bytes): ${sourceUrl}`);
  }
  return body;
}

async function importRow({ client, env, bucket, cdnBase, row }) {
  const sourceUrl = previewCardTraderImageUrl(row);
  if (!sourceUrl) {
    return { skipped: true, reason: 'no-preview-image' };
  }

  const slug = slugify(row.name) || `card-${row.id}`;
  const key = `previews/${row.id}_${slug}.jpg`;
  const preview = await download(sourceUrl);
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: preview,
      ContentType: 'image/jpeg',
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );

  const previewImageUrl = `${cdnBase}/${key}`;
  await updateRow(env, {
    id: row.id,
    preview_image_url: previewImageUrl,
    preview_object_key: key,
  });
  return { skipped: false, key, bytes: preview.length, sourceUrl };
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
  const batchSize = Number(process.env.PREVIEW_BATCH_SIZE || 50);
  const maxRows = Number(process.env.PREVIEW_MAX_ROWS || 0);
  const startOffset = Number(process.env.PREVIEW_OFFSET || 0);
  let cursorId = Number(process.env.PREVIEW_CURSOR_ID || 0);
  const missingOnly = process.env.PREVIEW_MISSING_ONLY === '1';
  const newestFirst = process.env.PREVIEW_NEWEST_FIRST === '1';
  const force = process.env.PREVIEW_FORCE === '1';
  const sortDirection = newestFirst ? 'desc' : 'asc';
  const ids = String(process.env.PREVIEW_IDS || '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => /^\d+$/.test(value));

  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  let offset = ids.length > 0 ? 0 : startOffset;
  const useCursor = ids.length === 0 && (missingOnly || cursorId > 0);
  let attempted = 0;
  let imported = 0;
  let skipped = 0;
  let failed = 0;

  while (true) {
    const rows = await fetchRows(env, {
      ids,
      limit: batchSize,
      offset,
      cursorId: useCursor ? cursorId : 0,
      missingOnly,
      sortDirection,
    });
    if (rows.length === 0) {
      break;
    }

    for (const row of rows) {
      attempted += 1;
      if (!force && row.preview_image_url) {
        skipped += 1;
        continue;
      }
      try {
        const result = await importRow({ client, env, bucket, cdnBase, row });
        if (result.skipped) {
          skipped += 1;
          console.log(`skipped ${row.id}: ${result.reason}`);
        } else {
          imported += 1;
          console.log(`imported ${row.id}: ${result.key} (${result.bytes} bytes)`);
        }
      } catch (error) {
        failed += 1;
        console.error(`failed ${row.id}: ${error.message}`);
      }
    }

    const lastRowId = Number(rows[rows.length - 1]?.id || 0);
    if (useCursor && lastRowId > 0) {
      cursorId = lastRowId;
    } else {
      offset += rows.length;
    }
    const processed = ids.length > 0 ? offset : (useCursor ? attempted : offset - startOffset);
    const resumeToken = useCursor ? `next cursor ${cursorId}` : `next offset ${offset}`;
    console.log(`processed ${processed}, ${resumeToken}, imported ${imported}, skipped ${skipped}, failed ${failed}`);
    if (ids.length > 0 || (maxRows > 0 && processed >= maxRows)) {
      break;
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
