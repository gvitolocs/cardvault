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

function normalizeCardTraderImageUrl(rawValue) {
  const rawUrl = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (
    !rawUrl ||
    rawUrl.includes('/preview_') ||
    rawUrl.includes('/fallbacks/card_uploader/')
  ) {
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

function fullCardTraderImageUrl(row) {
  const image = row.blueprint?.image;
  const candidates = [
    typeof image?.url === 'string' ? image.url : null,
    typeof row.blueprint?.image_url === 'string' ? row.blueprint.image_url : null,
    typeof row.cardtrader_image_url === 'string' ? row.cardtrader_image_url : null,
    typeof row.image_url === 'string' && row.image_url.includes('cardtrader.com')
      ? row.image_url
      : null,
  ];
  for (const candidate of candidates) {
    const normalized = normalizeCardTraderImageUrl(candidate);
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

function objectKeyForRow(row, sourceUrl) {
  if (row.cdn_object_key && !String(row.cdn_object_key).includes('/previews/')) {
    return row.cdn_object_key;
  }
  const ext = extensionFromUrl(sourceUrl);
  const slug = slugify(row.name) || `card-${row.id}`;
  return `${row.id}_${slug}.${ext}`;
}

async function fetchRows(env, {
  ids,
  limit,
  offset,
  cursorId,
  missingOnly,
  sortDirection,
}) {
  const url = new URL(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_blueprints`,
  );
  url.searchParams.set(
    'select',
    'id,name,cdn_object_key,cdn_image_url,image_url,cardtrader_image_url,blueprint',
  );
  if (ids.length > 0) {
    url.searchParams.set('id', `in.(${ids.join(',')})`);
  } else {
    if (missingOnly) {
      url.searchParams.set('or', '(cdn_image_url.is.null,cdn_object_key.is.null)');
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

async function updateRow(env, row) {
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
        image_url: row.cdn_image_url,
        cdn_image_url: row.cdn_image_url,
        cdn_object_key: row.cdn_object_key,
        cardtrader_image_url: row.cardtrader_image_url,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase update failed ${response.status}: ${await response.text()}`);
  }
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
    throw new Error(`${table} image update failed ${response.status}: ${await response.text()}`);
  }
}

async function syncProjectionImages(env, row) {
  const values = {
    image_url: row.cdn_image_url,
    cdn_image_url: row.cdn_image_url,
  };
  await patchTable(env, 'marketplace_cards', row.id, values);
  await patchTable(env, 'marketplace_card_versions', row.id, values);
}

async function upsertProjectionRowsViaSql(env, ids) {
  if (ids.length === 0) {
    return;
  }
  const token = env.SUPABASE_SECRET_ACCESS_TOKEN || env.SUPABASE_SECRET_ACCESS_KEY;
  if (!env.SUPABASE_PROJECT_REF || !token) {
    return;
  }

  const idValues = ids.map((id) => `(${Number(id)})`).join(',');
  const query = `
with imported_ids(id) as (
  values ${idValues}
),
marketplace_source as (
  select
    b.*,
    source.set_name,
    source.rarity,
    source.card_type,
    source.card_number,
    source.product_type
  from public.cardtrader_pokemon_blueprints b
  join imported_ids imported on imported.id = b.id
  cross join lateral (
    select
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as set_name,
      coalesce(
        nullif(b.blueprint->>'rarity', ''),
        nullif(b.blueprint->>'collector_rarity', ''),
        'Card'
      ) as rarity,
      coalesce(
        nullif(b.blueprint->>'card_type', ''),
        nullif(b.blueprint->>'type', ''),
        nullif(b.blueprint->>'category_name', ''),
        'Trading card'
      ) as card_type,
      coalesce(
        nullif(b.blueprint->>'number', ''),
        nullif(b.blueprint->>'collector_number', ''),
        nullif(b.blueprint->>'card_number', ''),
        b.version,
        b.id::text
      ) as card_number
  ) fields
  cross join lateral (
    select
      fields.*,
      public.classify_marketplace_product_type(
        b.name,
        fields.set_name,
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        fields.card_number,
        b.version,
        b.id
      ) as product_type
  ) source
  where b.cdn_image_url is not null
)
insert into public.marketplace_cards (
  card_id,
  name,
  version,
  image_url,
  cdn_image_url,
  preview_image_url,
  set_name,
  rarity,
  card_type,
  card_number,
  is_holo,
  is_foil,
  imported_at,
  projected_at,
  item_kind,
  product_type
)
select
  id,
  name,
  version,
  image_url,
  cdn_image_url,
  preview_image_url,
  set_name,
  rarity,
  card_type,
  card_number,
  lower(coalesce(blueprint->>'rarity', '')) like '%holo%',
  lower(coalesce(blueprint->>'rarity', '')) like '%holo%',
  imported_at,
  now(),
  case when product_type = 'card' then 'single' else 'product' end,
  product_type
from marketplace_source
on conflict (card_id) do update set
  name = excluded.name,
  version = excluded.version,
  image_url = excluded.image_url,
  cdn_image_url = excluded.cdn_image_url,
  preview_image_url = excluded.preview_image_url,
  set_name = excluded.set_name,
  rarity = excluded.rarity,
  card_type = excluded.card_type,
  card_number = excluded.card_number,
  is_holo = excluded.is_holo,
  is_foil = excluded.is_foil,
  imported_at = excluded.imported_at,
  projected_at = now(),
  item_kind = excluded.item_kind,
  product_type = excluded.product_type;

with imported_ids(id) as (
  values ${idValues}
),
version_source as (
  select
    b.*,
    source.expansion_name,
    source.expansion_number,
    source.product_type
  from public.cardtrader_pokemon_blueprints b
  join imported_ids imported on imported.id = b.id
  cross join lateral (
    select
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as expansion_name,
      coalesce(
        nullif(b.blueprint->>'number', ''),
        nullif(b.blueprint->>'collector_number', ''),
        nullif(b.blueprint->>'card_number', ''),
        b.version,
        b.id::text
      ) as expansion_number
  ) fields
  cross join lateral (
    select
      fields.*,
      public.classify_marketplace_product_type(
        b.name,
        fields.expansion_name,
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        fields.expansion_number,
        b.version,
        b.id
      ) as product_type
  ) source
  where b.cdn_image_url is not null
)
insert into public.marketplace_card_versions (
  card_id,
  name,
  expansion_name,
  expansion_number,
  expansion_number_int,
  blueprint_id,
  image_url,
  cdn_image_url,
  preview_image_url,
  projected_at,
  product_type
)
select
  id,
  name,
  expansion_name,
  expansion_number,
  public.marketplace_expansion_number_int(expansion_number),
  id,
  image_url,
  cdn_image_url,
  preview_image_url,
  now(),
  product_type
from version_source
on conflict (card_id) do update set
  name = excluded.name,
  expansion_name = excluded.expansion_name,
  expansion_number = excluded.expansion_number,
  expansion_number_int = excluded.expansion_number_int,
  blueprint_id = excluded.blueprint_id,
  image_url = excluded.image_url,
  cdn_image_url = excluded.cdn_image_url,
  preview_image_url = excluded.preview_image_url,
  projected_at = now(),
  product_type = excluded.product_type;
`;

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
    throw new Error(`Projection upsert failed ${response.status}: ${await response.text()}`);
  }
}

async function refreshProjection(env, functionName) {
  const response = await fetch(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/${functionName}`,
    {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    },
  );
  if (!response.ok) {
    throw new Error(`${functionName} failed ${response.status}: ${await response.text()}`);
  }
  return response.text();
}

async function download(sourceUrl) {
  const response = await fetch(sourceUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Pokoin image importer)',
      Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    },
  });
  if (!response.ok) {
    throw new Error(`Image download failed ${response.status}: ${sourceUrl}`);
  }
  const body = Buffer.from(await response.arrayBuffer());
  if (body.length < 1024) {
    throw new Error(`Image download too small (${body.length} bytes): ${sourceUrl}`);
  }
  return body;
}

async function importRow({ client, env, bucket, cdnBase, row }) {
  const sourceUrl = fullCardTraderImageUrl(row);
  if (!sourceUrl) {
    return { skipped: true, reason: 'no-full-image' };
  }

  const key = objectKeyForRow(row, sourceUrl);
  const ext = extensionFromUrl(sourceUrl);
  const image = await download(sourceUrl);
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: image,
      ContentType: contentTypeForExtension(ext),
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );

  const cdnImageUrl = `${cdnBase}/${key}`;
  await updateRow(env, {
    id: row.id,
    cdn_image_url: cdnImageUrl,
    cdn_object_key: key,
    cardtrader_image_url: sourceUrl,
  });
  await syncProjectionImages(env, {
    id: row.id,
    cdn_image_url: cdnImageUrl,
  });
  return { skipped: false, key, bytes: image.length, sourceUrl };
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
  const batchSize = Number(process.env.FULL_IMAGE_BATCH_SIZE || 50);
  const maxRows = Number(process.env.FULL_IMAGE_MAX_ROWS || 0);
  const startOffset = Number(process.env.FULL_IMAGE_OFFSET || 0);
  let cursorId = Number(process.env.FULL_IMAGE_CURSOR_ID || 0);
  const missingOnly = process.env.FULL_IMAGE_MISSING_ONLY === '1';
  const newestFirst = process.env.FULL_IMAGE_NEWEST_FIRST === '1';
  const sortDirection = newestFirst ? 'desc' : 'asc';
  const ids = String(process.env.FULL_IMAGE_IDS || '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => /^\d+$/.test(value));
  const refresh = process.env.REFRESH_MARKETPLACE_PROJECTIONS === '1';

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

    const importedIds = [];
    for (const row of rows) {
      attempted += 1;
      try {
        const result = await importRow({ client, env, bucket, cdnBase, row });
        if (result.skipped) {
          skipped += 1;
          console.log(`skipped ${row.id}: ${result.reason}`);
        } else {
          imported += 1;
          importedIds.push(row.id);
          console.log(`imported ${row.id}: ${result.key} (${result.bytes} bytes)`);
        }
      } catch (error) {
        failed += 1;
        console.error(`failed ${row.id}: ${error.message}`);
      }
    }
    await upsertProjectionRowsViaSql(env, importedIds);

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

  if (refresh) {
    console.log('refreshing marketplace projections...');
    await refreshProjection(env, 'refresh_marketplace_cards_from_blueprints');
    await refreshProjection(env, 'refresh_marketplace_card_versions');
    console.log('refreshed marketplace projections');
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
