const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');

function readEnv(filePath) {
  const values = {};
  if (fs.existsSync(filePath)) {
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
  }
  return values;
}

function required(env, key) {
  if (!env[key]) {
    throw new Error(`Missing ${key}`);
  }
  return env[key];
}

function marketplaceDatabaseUrl(env) {
  if (env.MARKETPLACE_DATABASE_URL) {
    return env.MARKETPLACE_DATABASE_URL;
  }
  const user = encodeURIComponent(required(env, 'MARKETPLACE_DB_USER'));
  const password = encodeURIComponent(required(env, 'MARKETPLACE_DB_PASSWORD'));
  const host = required(env, 'MARKETPLACE_DB_PUBLIC_HOST');
  const port = env.MARKETPLACE_DB_PORT || '5432';
  const database = encodeURIComponent(required(env, 'MARKETPLACE_DB_NAME'));
  return `postgresql://${user}:${password}@${host}:${port}/${database}`;
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

function fullImageUrls(row) {
  const image = row.blueprint?.image;
  const candidates = [
    typeof image?.url === 'string' ? image.url : null,
    typeof image?.show?.url === 'string' ? image.show.url : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof row.cardtrader_image_url === 'string' ? row.cardtrader_image_url : null,
    typeof row.image_url === 'string' && row.image_url.includes('cardtrader.com')
      ? row.image_url
      : null,
  ];
  const fullCandidates = candidates
    .map((candidate) => normalizeCardTraderUrl(candidate, { allowPreview: false }))
    .filter(Boolean);
  if (fullCandidates.length > 0) {
    return [...new Set(fullCandidates)];
  }
  // Some CardTrader rows only expose a preview asset. Import it as the full image
  // too so the app never renders directly from CardTrader.
  return previewImageUrls(row);
}

function previewImageUrls(row) {
  const image = row.blueprint?.image;
  const candidates = [
    typeof image?.preview?.url === 'string' ? image.preview.url : null,
    typeof row.preview_image_url === 'string' && row.preview_image_url.includes('cardtrader.com')
      ? row.preview_image_url
      : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof image?.show?.url === 'string' ? image.show.url : null,
    typeof image?.url === 'string' ? image.url : null,
  ];
  return [...new Set(candidates
    .map((candidate) => normalizeCardTraderUrl(candidate, { allowPreview: true }))
    .filter(Boolean))];
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

function extensionFromUrl(url) {
  const pathname = new URL(url).pathname;
  const match = pathname.match(/\.([a-zA-Z0-9]+)$/);
  const ext = match ? match[1].toLowerCase() : 'jpg';
  return ext === 'jpeg' ? 'jpg' : ext;
}

function contentTypeForExtension(ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

function extensionFromContentType(contentType) {
  const normalized = String(contentType || '').toLowerCase();
  if (normalized.includes('image/webp')) return 'webp';
  if (normalized.includes('image/png')) return 'png';
  if (normalized.includes('image/gif')) return 'gif';
  if (normalized.includes('image/jpeg') || normalized.includes('image/jpg')) return 'jpg';
  return null;
}

function imageFormatFromBytes(body) {
  if (!Buffer.isBuffer(body) || body.length < 12) return null;
  if (body[0] === 0xff && body[1] === 0xd8 && body[2] === 0xff) return 'jpg';
  if (body.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return 'png';
  }
  if (
    body.slice(0, 6).toString('ascii') === 'GIF87a' ||
    body.slice(0, 6).toString('ascii') === 'GIF89a'
  ) {
    return 'gif';
  }
  if (body.slice(0, 4).toString('ascii') === 'RIFF' && body.slice(8, 12).toString('ascii') === 'WEBP') {
    return 'webp';
  }
  return null;
}

async function download(sourceUrl, minBytes) {
  const response = await fetch(sourceUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Pokoin Oracle image importer)',
      Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    },
  });
  if (!response.ok) {
    throw new Error(`download failed ${response.status}: ${sourceUrl}`);
  }
  const body = Buffer.from(await response.arrayBuffer());
  if (body.length < minBytes) {
    throw new Error(`download too small (${body.length} bytes): ${sourceUrl}`);
  }
  return {
    body,
    contentType: response.headers.get('content-type') || '',
  };
}

function objectKeyForRow(row, sourceUrl, ext) {
  const forceSuffix = String(process.env.ORACLE_IMAGE_FULL_KEY_SUFFIX || '').trim();
  if (forceSuffix) {
    const slug = slugify(row.name) || `card-${row.id}`;
    return `${row.id}_${slug}-${forceSuffix}.${ext}`;
  }
  if (row.cdn_object_key && !String(row.cdn_object_key).startsWith('previews/')) {
    return String(row.cdn_object_key).replace(/\.[^.]+$/, `.${ext}`);
  }
  const slug = slugify(row.name) || `card-${row.id}`;
  return `${row.id}_${slug}.${ext}`;
}

function previewObjectKeyForRow(row, ext) {
  if (row.preview_object_key) {
    return String(row.preview_object_key).replace(/\.[^.]+$/, `.${ext}`);
  }
  const slug = slugify(row.name) || `card-${row.id}`;
  return `previews/${row.id}_${slug}.${ext}`;
}

async function firstDownload(candidates, minBytes) {
  const errors = [];
  for (const sourceUrl of candidates) {
    try {
      return {
        sourceUrl,
        ...(await download(sourceUrl, minBytes)),
      };
    } catch (error) {
      errors.push(`${sourceUrl}: ${error.message}`);
    }
  }
  throw new Error(errors.join(' | ') || 'no candidates');
}

async function uploadObject(client, { bucket, key, body, ext }) {
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentTypeForExtension(ext),
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );
}

async function fetchRows(pool, { ids, limit, offset, cursorId, newestFirst, mode }) {
  const values = [];
  const where = [];
  const useOffset = ids.length === 0 && cursorId < 0;
  const forceFull = process.env.ORACLE_IMAGE_FORCE_FULL === '1';
  const forcePreview = process.env.ORACLE_IMAGE_FORCE_PREVIEW === '1';
  if (ids.length > 0) {
    values.push(ids);
    where.push(`id = any($${values.length}::bigint[])`);
  } else {
    if (mode !== 'preview' && !forceFull) {
      where.push(`(coalesce(cdn_image_url, '') = '' or image_url like 'https://cardtrader.com/%')`);
    }
    if (mode !== 'full' && !forcePreview) {
      where.push(`(coalesce(preview_image_url, '') = '' or preview_image_url like 'https://cardtrader.com/%')`);
    }
    where.push(`
      (
        (coalesce(blueprint #>> '{image,url}', '') <> '' and coalesce(blueprint #>> '{image,url}', '') not like '%/fallbacks/card_uploader/%')
        or (coalesce(blueprint #>> '{image,show,url}', '') <> '' and coalesce(blueprint #>> '{image,show,url}', '') not like '%/fallbacks/card_uploader/%')
        or (coalesce(blueprint #>> '{image,preview,url}', '') <> '' and coalesce(blueprint #>> '{image,preview,url}', '') not like '%/fallbacks/card_uploader/%')
        or (coalesce(blueprint->>'image_url', '') <> '' and coalesce(blueprint->>'image_url', '') not like '%/fallbacks/card_uploader/%')
        or (coalesce(cardtrader_image_url, '') <> '' and cardtrader_image_url not like '%/fallbacks/card_uploader/%')
        or (image_url like 'https://cardtrader.com/%' and image_url not like '%/fallbacks/card_uploader/%')
        or (preview_image_url like 'https://cardtrader.com/%' and preview_image_url not like '%/fallbacks/card_uploader/%')
      )
    `);
    if (cursorId > 0) {
      values.push(cursorId);
      where.push(newestFirst ? `id < $${values.length}` : `id > $${values.length}`);
    }
  }
  values.push(limit);
  const limitPlaceholder = `$${values.length}`;
  let offsetPlaceholder = '0';
  if (useOffset) {
    values.push(offset);
    offsetPlaceholder = `$${values.length}`;
  }
  const result = await pool.query(
    `
      select
        id, name, image_url, cdn_image_url, cdn_object_key, cardtrader_image_url,
        preview_image_url, preview_object_key, blueprint
      from public.cardtrader_pokemon_blueprints
      ${where.length > 0 ? `where ${where.join(' and ')}` : ''}
      order by id ${newestFirst ? 'desc' : 'asc'}
      limit ${limitPlaceholder}
      offset ${offsetPlaceholder}
    `,
    values,
  );
  return result.rows;
}

async function updateOracleRows(pool, row, updates) {
  const sets = [];
  const values = [];
  for (const [key, value] of Object.entries(updates)) {
    values.push(value);
    sets.push(`${key} = $${values.length}`);
  }
  values.push(row.id);
  await pool.query(
    `update public.cardtrader_pokemon_blueprints set ${sets.join(', ')} where id = $${values.length}`,
    values,
  );
  await pool.query(
    `
      update public.marketplace_cards
      set
        image_url = coalesce($1, image_url),
        cdn_image_url = coalesce($2, cdn_image_url),
        preview_image_url = coalesce($3, preview_image_url),
        projected_at = now()
      where card_id = $4
    `,
    [updates.image_url || null, updates.cdn_image_url || null, updates.preview_image_url || null, row.id],
  );
  await pool.query(
    `
      update public.marketplace_card_versions
      set
        image_url = coalesce($1, image_url),
        cdn_image_url = coalesce($2, cdn_image_url),
        preview_image_url = coalesce($3, preview_image_url),
        projected_at = now()
      where card_id = $4
    `,
    [updates.image_url || null, updates.cdn_image_url || null, updates.preview_image_url || null, row.id],
  );
  await pool.query(
    `
      update public.marketplace_search_candidates
      set
        image_url = coalesce($1, image_url),
        cdn_image_url = coalesce($2, cdn_image_url),
        preview_image_url = coalesce($3, preview_image_url),
        projected_at = now()
      where card_id = $4
    `,
    [updates.image_url || null, updates.cdn_image_url || null, updates.preview_image_url || null, row.id],
  );
}

async function importRow({ client, pool, bucket, cdnBase, row, mode }) {
  const updates = {};
  const imported = [];
  const forceFull = process.env.ORACLE_IMAGE_FORCE_FULL === '1';
  const forcePreview = process.env.ORACLE_IMAGE_FORCE_PREVIEW === '1';

  if (
    mode !== 'preview' &&
    (forceFull ||
      !row.cdn_image_url ||
      String(row.image_url || '').includes('cardtrader.com'))
  ) {
    const source = await firstDownload(fullImageUrls(row), 1024);
    const ext =
      imageFormatFromBytes(source.body) ||
      extensionFromContentType(source.contentType) ||
      extensionFromUrl(source.sourceUrl);
    const key = objectKeyForRow(row, source.sourceUrl, ext);
    await uploadObject(client, { bucket, key, body: source.body, ext });
    const url = `${cdnBase}/${key}`;
    updates.image_url = url;
    updates.cdn_image_url = url;
    updates.cdn_object_key = key;
    if (process.env.ORACLE_IMAGE_KEEP_SOURCE_URLS === '1') {
      updates.cardtrader_image_url = source.sourceUrl;
    }
    imported.push(`full:${key}`);
  }

  if (
    mode !== 'full' &&
    (forcePreview ||
      !row.preview_image_url ||
      String(row.preview_image_url).includes('cardtrader.com'))
  ) {
    const source = await firstDownload(previewImageUrls(row), 256);
    const ext =
      imageFormatFromBytes(source.body) ||
      extensionFromContentType(source.contentType) ||
      extensionFromUrl(source.sourceUrl);
    const key = previewObjectKeyForRow(row, ext);
    await uploadObject(client, { bucket, key, body: source.body, ext });
    updates.preview_image_url = `${cdnBase}/${key}`;
    updates.preview_object_key = key;
    imported.push(`preview:${key}`);
  }

  if (Object.keys(updates).length > 0) {
    await updateOracleRows(pool, row, updates);
  }
  return imported;
}

async function main() {
  const localEnv = readEnv(path.resolve('.env.local'));
  const oracleEnv = readEnv(process.env.ORACLE_ENV_FILE || '/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env');
  const env = { ...localEnv, ...oracleEnv, ...process.env };
  required(env, 'CLOUDFLARE_ACCOUNT_ID');
  required(env, 'R2_ACCESS_KEY_ID');
  required(env, 'R2_SECRET_ACCESS_KEY');

  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const batchSize = Number(env.ORACLE_IMAGE_BATCH_SIZE || 25);
  const maxRows = Number(env.ORACLE_IMAGE_MAX_ROWS || 0);
  const newestFirst = env.ORACLE_IMAGE_NEWEST_FIRST === '1';
  const mode = env.ORACLE_IMAGE_MODE || 'both';
  const ids = String(env.ORACLE_IMAGE_IDS || '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => /^\d+$/.test(value));
  let offset = Number(env.ORACLE_IMAGE_OFFSET || 0);
  let cursorId = Number(env.ORACLE_IMAGE_CURSOR_ID || 0);
  const useCursor = ids.length === 0 && cursorId >= 0;

  const pool = new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  let attempted = 0;
  let imported = 0;
  let failed = 0;
  try {
    while (true) {
      const rows = await fetchRows(pool, {
        ids,
        limit: batchSize,
        offset,
        cursorId: useCursor ? cursorId : 0,
        newestFirst,
        mode,
      });
      if (rows.length === 0) break;

      for (const row of rows) {
        attempted += 1;
        try {
          const result = await importRow({ client, pool, bucket, cdnBase, row, mode });
          if (result.length > 0) {
            imported += 1;
            console.log(`imported ${row.id}: ${result.join(', ')}`);
          } else {
            console.log(`skipped ${row.id}: already-cdn`);
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
      const processed = ids.length > 0 ? attempted : useCursor ? attempted : offset;
      console.log(`processed ${processed}; next ${useCursor ? `cursor ${cursorId}` : `offset ${offset}`}; imported ${imported}; failed ${failed}`);
      if (ids.length > 0 || (maxRows > 0 && processed >= maxRows)) break;
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
