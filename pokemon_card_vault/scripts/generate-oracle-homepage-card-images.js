const fs = require('node:fs');
const path = require('node:path');
const {
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const sharp = require('sharp');

const HOMEPAGE_REFERENCE_WIDTH = 240;
const DEFAULT_HOMEPAGE_QUALITY = 82;
const DEFAULT_CONCURRENCY = 4;
const DEFAULT_ERROR_LIMIT = 25;
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

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

function parseArgs(argv) {
  const options = {
    apply: false,
    verifyCoverage: false,
    ids: [],
    limit: 25,
    concurrency: DEFAULT_CONCURRENCY,
    errorLimit: DEFAULT_ERROR_LIMIT,
    startId: '',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--verify-coverage') {
      options.verifyCoverage = true;
    } else if (arg.startsWith('--ids=')) {
      options.ids = arg
        .slice('--ids='.length)
        .split(',')
        .map((value) => value.trim())
        .filter((value) => /^\d+$/.test(value));
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? 0 : Number(raw);
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Number(arg.slice('--concurrency='.length));
    } else if (arg.startsWith('--error-limit=')) {
      options.errorLimit = Number(arg.slice('--error-limit='.length));
    } else if (arg.startsWith('--start-id=')) {
      const value = arg.slice('--start-id='.length).trim();
      options.startId = /^\d+$/.test(value) ? value : '';
    }
  }
  return options;
}

function objectKeyFromUrl(url, cdnBase) {
  const text = String(url || '').trim();
  if (!text) {
    return '';
  }
  try {
    const parsed = new URL(text);
    const base = new URL(cdnBase);
    if (parsed.hostname !== base.hostname) {
      return '';
    }
    return parsed.pathname.replace(/^\/+/, '');
  } catch {
    return text.replace(/^\/card-images\//, '').replace(/^\/+/, '');
  }
}

function homepageKeyForFullKey(fullKey) {
  const key = String(fullKey || '').trim();
  const dirname = path.posix.dirname(key);
  const ext = path.posix.extname(key);
  const basename = path.posix.basename(key, ext);
  const filename = `${basename}_homepage.webp`;
  return dirname === '.' ? filename : `${dirname}/${filename}`;
}

function homepageKeyForRow(row, fullKey) {
  const existing = String(row.homepage_object_key || '').trim();
  return existing.endsWith('_homepage.webp')
    ? existing
    : homepageKeyForFullKey(fullKey);
}

async function objectExists(client, bucket, key) {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (error) {
    if (error?.$metadata?.httpStatusCode === 404 || error?.name === 'NotFound') {
      return false;
    }
    throw error;
  }
}

async function getR2Object(client, bucket, key) {
  const object = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const chunks = [];
  for await (const chunk of object.Body) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function imageMetadata(body) {
  const metadata = await sharp(body).metadata();
  return {
    width: Number(metadata.width || 0),
    height: Number(metadata.height || 0),
    format: metadata.format || '',
  };
}

function isAtLeastReference(metadata, referenceWidth) {
  return metadata.width >= referenceWidth;
}

function isExpectedHomepageForSource(homepageMetadata, sourceMetadata, referenceWidth) {
  if (!homepageMetadata.width || !sourceMetadata.width) {
    return false;
  }
  return homepageMetadata.width === Math.min(sourceMetadata.width, referenceWidth);
}

function projectedResizeDimensions(metadata, referenceWidth) {
  if (!metadata.width || !metadata.height) {
    return `${referenceWidth}w`;
  }
  if (metadata.width <= referenceWidth) {
    return `${metadata.width}x${metadata.height}`;
  }
  return `${referenceWidth}x${Math.round((metadata.height * referenceWidth) / metadata.width)}`;
}

async function ensureColumns(pool) {
  await pool.query(`
    alter table public.cardtrader_pokemon_blueprints
      add column if not exists homepage_image_url text;
    alter table public.cardtrader_pokemon_blueprints
      add column if not exists homepage_object_key text;
    alter table public.marketplace_cards
      add column if not exists homepage_image_url text;
    alter table public.marketplace_card_versions
      add column if not exists homepage_image_url text;
    alter table public.marketplace_search_candidates
      add column if not exists homepage_image_url text;
  `);
}

function normalizedLimit(value) {
  if (value === 0) {
    return 0;
  }
  return Math.max(1, Math.min(Number(value) || 25, 100000));
}

async function fetchRows(pool, { ids, limit, startId }) {
  const values = [];
  const where = [
    `coalesce(preview_image_url, preview_object_key, cdn_image_url, cdn_object_key, image_url, '') <> ''`,
  ];
  if (ids.length > 0) {
    values.push(ids);
    where.push(`id = any($${values.length}::bigint[])`);
  } else if (startId) {
    values.push(startId);
    where.push(`id > $${values.length}::bigint`);
  }
  const rowLimit = normalizedLimit(limit);
  const limitClause = rowLimit > 0 ? `limit $${values.length + 1}` : '';
  if (rowLimit > 0) {
    values.push(rowLimit);
  }
  const result = await pool.query(
    `
      select id, name, cdn_image_url, cdn_object_key, preview_image_url,
        preview_object_key, homepage_image_url, homepage_object_key
      from public.cardtrader_pokemon_blueprints
      where ${where.join(' and ')}
      order by id asc
      ${limitClause}
    `,
    values,
  );
  return result.rows;
}

async function updateHomepage(pool, row, homepageUrl, homepageKey) {
  await pool.query(
    `
      update public.cardtrader_pokemon_blueprints
      set homepage_image_url = $1, homepage_object_key = $2
      where id = $3
    `,
    [homepageUrl, homepageKey, row.id],
  );
  for (const table of [
    'marketplace_cards',
    'marketplace_card_versions',
    'marketplace_search_candidates',
  ]) {
    await pool.query(
      `update public.${table} set homepage_image_url = $1, projected_at = now() where card_id = $2`,
      [homepageUrl, row.id],
    );
  }
}

async function verifyCoverage(pool) {
  const coverage = await pool.query(`
    with eligible as (
      select
        id,
        cdn_image_url,
        cdn_object_key,
        preview_image_url,
        preview_object_key,
        homepage_image_url,
        homepage_object_key
      from public.cardtrader_pokemon_blueprints
      where coalesce(preview_image_url, preview_object_key, cdn_image_url, cdn_object_key, image_url, '') <> ''
    )
    select
      count(*)::int as eligible_blueprints,
      count(*) filter (where coalesce(homepage_image_url, '') <> '')::int as populated_homepage_images,
      count(*) filter (where coalesce(homepage_image_url, '') = '')::int as missing_homepage_images,
      count(*) filter (
        where coalesce(homepage_object_key, homepage_image_url, '') like '%_homepage.webp'
      )::int as generated_homepage_images,
      count(*) filter (
        where coalesce(homepage_image_url, '') <> ''
          and (
            homepage_object_key = preview_object_key
            or homepage_image_url = preview_image_url
          )
      )::int as preview_linked_fallbacks,
      count(*) filter (
        where coalesce(homepage_image_url, '') <> ''
          and coalesce(homepage_object_key, homepage_image_url, '') not like '%_homepage.webp'
          and not (
            homepage_object_key = preview_object_key
            or homepage_image_url = preview_image_url
          )
      )::int as other_homepage_links
    from eligible
  `);
  const snapshotCoverage = await pool.query(`
    with source_rows as (
      select
        card_id,
        homepage_image_url
      from public.marketplace_search_candidates
      where coalesce(homepage_image_url, '') <> ''
    ),
    snapshot_cards as (
      select card
      from jsonb_array_elements(public.get_marketplace_home_snapshot(500)->'cards') as cards(card)
    )
    select
      count(*)::int as snapshot_cards,
      count(*) filter (where coalesce(card->>'homepageImageUrl', '') <> '')::int
        as snapshot_homepage_images,
      count(*) filter (
        where coalesce(card->>'homepageImageUrl', '') <> ''
          and coalesce(card->>'homepageImageUrl', '') = coalesce(card->>'previewImageUrl', '')
      )::int as snapshot_preview_fallbacks,
      count(*) filter (
        where source_rows.homepage_image_url is not null
          and coalesce(card->>'homepageImageUrl', '') <> source_rows.homepage_image_url
          and coalesce(card->>'homepageImageUrl', '') <>
            regexp_replace(source_rows.homepage_image_url, '^https://cdn\\.pokoin\\.com/', '/card-images/')
      )::int as snapshot_homepage_mismatches
    from snapshot_cards
    left join source_rows on source_rows.card_id = (card->>'id')::bigint
  `);
  const snapshotSamples = await pool.query(`
    with source_rows as (
      select
        card_id,
        name,
        preview_image_url,
        homepage_image_url
      from public.marketplace_search_candidates
      where coalesce(homepage_image_url, '') <> ''
    ),
    snapshot_cards as (
      select card
      from jsonb_array_elements(public.get_marketplace_home_snapshot(500)->'cards') as cards(card)
    )
    select
      source_rows.card_id as id,
      source_rows.name,
      source_rows.homepage_image_url as expected_homepage_image_url,
      card->>'homepageImageUrl' as snapshot_homepage_image_url,
      card->>'previewImageUrl' as snapshot_preview_image_url
    from snapshot_cards
    join source_rows on source_rows.card_id = (card->>'id')::bigint
    where coalesce(card->>'homepageImageUrl', '') <> source_rows.homepage_image_url
      and coalesce(card->>'homepageImageUrl', '') <>
        regexp_replace(source_rows.homepage_image_url, '^https://cdn\\.pokoin\\.com/', '/card-images/')
    order by source_rows.card_id asc
    limit 20
  `);
  const samples = await pool.query(`
    select
      id,
      name,
      cdn_object_key,
      preview_object_key,
      homepage_object_key,
      homepage_image_url
    from public.cardtrader_pokemon_blueprints
    where coalesce(preview_image_url, preview_object_key, cdn_image_url, cdn_object_key, image_url, '') <> ''
      and coalesce(homepage_image_url, '') = ''
    order by id asc
    limit 20
  `);
  console.log(JSON.stringify({
    coverage: coverage.rows[0],
    snapshotCoverage: snapshotCoverage.rows[0],
    missingSamples: samples.rows,
    snapshotMismatchSamples: snapshotSamples.rows,
  }, null, 2));
}

async function buildHomepageImage(fullBody, referenceWidth, quality) {
  return sharp(fullBody)
    .rotate()
    .resize({
      width: referenceWidth,
      withoutEnlargement: true,
    })
    .webp({ quality })
    .toBuffer();
}

function createSummary() {
  return {
    processed: 0,
    generated: 0,
    recreated: 0,
    linked: 0,
    skipped: 0,
    errors: 0,
    samples: [],
  };
}

function updateSummary(summary, result) {
  summary.processed += 1;
  const action = String(result.action || '');
  if (action.includes('failed')) {
    summary.errors += 1;
  } else if (action.includes('skip')) {
    summary.skipped += 1;
  } else if (action.includes('recreate') || action.includes('recreated')) {
    summary.recreated += 1;
  } else if (action.includes('create') || action.includes('created')) {
    summary.generated += 1;
  } else if (action.includes('link') || action.includes('linked')) {
    summary.linked += 1;
  }
  if (summary.samples.length < 10) {
    summary.samples.push(result);
  }
}

function shouldPrintResult(result, ids) {
  if (ids.length > 0) {
    return true;
  }
  const action = String(result.action || '');
  return action.includes('failed') || action.includes('skip');
}

async function processRow({ client, pool, bucket, cdnBase, referenceWidth, row, apply, quality }) {
  const previewKey =
    row.preview_object_key || objectKeyFromUrl(row.preview_image_url, cdnBase);
  const fullKey = row.cdn_object_key || objectKeyFromUrl(row.cdn_image_url, cdnBase);
  let previewStatus = previewKey ? 'not-read' : 'missing';
  if (!previewKey && !fullKey) {
    return { id: row.id, action: 'skip', reason: 'missing-object-key' };
  }

  if (previewKey) {
    const previewUrl = row.preview_image_url || `${cdnBase}/${previewKey}`;
    let previewMetadata;
    try {
      const previewBody = await getR2Object(client, bucket, previewKey);
      previewMetadata = await imageMetadata(previewBody);
      previewStatus = `${previewMetadata.width}x${previewMetadata.height}`;
    } catch (error) {
      previewStatus = `read-failed:${error.message}`;
      if (!fullKey) {
        return {
          id: row.id,
          action: 'skip',
          reason: 'preview-read-failed-and-missing-full-source',
          previewKey,
          error: error.message,
        };
      }
    }
    if (previewMetadata && !fullKey && isAtLeastReference(previewMetadata, referenceWidth)) {
      if (apply) {
        await updateHomepage(pool, row, previewUrl, previewKey);
      }
      return {
        id: row.id,
        action: apply ? 'linked-preview-fallback' : 'would-link-preview-fallback',
        preview: `${previewMetadata.width}x${previewMetadata.height}`,
        reason: 'missing-full-source-preview-at-reference-width',
        decision: 'fallback-only-no-full-source',
        homepageUrl: previewUrl,
      };
    }
    if (previewMetadata && !fullKey) {
      return {
        id: row.id,
        action: 'skip',
        preview: `${previewMetadata.width}x${previewMetadata.height}`,
        reason: 'preview-below-reference-and-missing-full-source',
        decision: 'no-safe-homepage-source',
      };
    }
  }

  const homepageKey = homepageKeyForRow(row, fullKey);
  const homepageUrl = `${cdnBase}/${homepageKey}`;
  const exists = await objectExists(client, bucket, homepageKey);
  let homepageMetadata;
  if (exists) {
    const homepageBody = await getR2Object(client, bucket, homepageKey);
    homepageMetadata = await imageMetadata(homepageBody);
  }
  let fullMetadata;
  const fullBody = await getR2Object(client, bucket, fullKey);
  fullMetadata = await imageMetadata(fullBody);
  if (
    exists &&
    homepageMetadata &&
    isExpectedHomepageForSource(homepageMetadata, fullMetadata, referenceWidth)
  ) {
    if (apply) {
      await updateHomepage(pool, row, homepageUrl, homepageKey);
    }
    return {
      id: row.id,
      action: apply ? 'linked-existing-homepage' : 'would-link-existing-homepage',
      preview: previewStatus === 'not-read' ? 'below-reference-width' : previewStatus,
      decision: 'existing-homepage-matches-source-width',
      homepage: `${homepageMetadata.width}x${homepageMetadata.height}`,
      source: `${fullMetadata.width}x${fullMetadata.height}`,
      homepageKey,
      homepageUrl,
    };
  }
  if (apply) {
    const homepageBody = await buildHomepageImage(fullBody, referenceWidth, quality);
    await client.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: homepageKey,
        Body: homepageBody,
        ContentType: 'image/webp',
        CacheControl: 'public, max-age=31536000, immutable',
      }),
    );
  }
  if (apply) {
    await updateHomepage(pool, row, homepageUrl, homepageKey);
  }
  return {
    id: row.id,
    action: apply
      ? (exists ? 'recreated-homepage' : 'created-homepage')
      : (exists ? 'would-recreate-homepage' : 'would-create-homepage'),
    preview: previewStatus === 'not-read' ? 'below-reference-width' : previewStatus,
    existingHomepage: homepageMetadata
      ? `${homepageMetadata.width}x${homepageMetadata.height}`
      : undefined,
    decision: exists
      ? 'existing-homepage-below-reference-regenerate-from-source'
      : 'generate-from-source',
    source: fullMetadata ? `${fullMetadata.width}x${fullMetadata.height}` : 'not-read-existing-homepage',
    homepage: fullMetadata ? projectedResizeDimensions(fullMetadata, referenceWidth) : `${referenceWidth}w`,
    homepageKey,
    homepageUrl,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const localEnv = readEnv(path.resolve('.env.local'));
  const oracleEnv = readEnv(process.env.ORACLE_ENV_FILE || DEFAULT_ORACLE_ENV_FILE);
  const env = { ...localEnv, ...oracleEnv, ...process.env };

  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');
  const referenceWidth = Number(env.HOMEPAGE_IMAGE_REFERENCE_WIDTH || HOMEPAGE_REFERENCE_WIDTH);
  const quality = Number(env.HOMEPAGE_IMAGE_QUALITY || DEFAULT_HOMEPAGE_QUALITY);
  const ids = options.ids.length > 0
    ? options.ids
    : String(env.HOMEPAGE_IMAGE_IDS || '')
      .split(',')
      .map((value) => value.trim())
      .filter((value) => /^\d+$/.test(value));
  const limit = options.limit === 0
    ? 0
    : Number(env.HOMEPAGE_IMAGE_MAX_ROWS || options.limit || 25);
  const startId = ids.length > 0 ? '' : options.startId;
  const concurrency = Math.max(1, Math.min(Number(options.concurrency) || DEFAULT_CONCURRENCY, 100));
  const errorLimit = Math.max(1, Number(options.errorLimit) || DEFAULT_ERROR_LIMIT);

  const pool = new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    max: Math.min(concurrency, 25),
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });

  try {
    if (options.verifyCoverage) {
      await verifyCoverage(pool);
      return;
    }
    required(env, 'CLOUDFLARE_ACCOUNT_ID');
    required(env, 'R2_ACCESS_KEY_ID');
    required(env, 'R2_SECRET_ACCESS_KEY');
    const client = new S3Client({
      region: 'auto',
      endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      },
    });
    if (options.apply) {
      await ensureColumns(pool);
    }
    const rows = await fetchRows(pool, { ids, limit, startId });
    console.log(`homepage reference width: ${referenceWidth}px`);
    console.log(`rows: ${rows.length}; concurrency: ${concurrency}; apply: ${options.apply}; startId: ${startId || 'none'}`);
    const summary = createSummary();
    let nextIndex = 0;
    let systemicError;
    async function worker() {
      while (nextIndex < rows.length && !systemicError) {
        const row = rows[nextIndex];
        nextIndex += 1;
        let result;
        try {
          result = await processRow({
            client,
            pool,
            bucket,
            cdnBase,
            referenceWidth,
            row,
            apply: options.apply,
            quality,
          });
        } catch (error) {
          result = { id: row.id, action: 'failed', error: error.message };
        }
        updateSummary(summary, result);
        if (shouldPrintResult(result, ids)) {
          const printable = { ...result };
          if (printable.error && printable.error.length > 240) {
            printable.error = `${printable.error.slice(0, 240)}...`;
          }
          console.log(JSON.stringify(printable));
        }
        if (summary.errors >= errorLimit) {
          systemicError = new Error(`stopping after ${summary.errors} errors`);
        }
        if (!ids.length && summary.processed % 500 === 0) {
          console.log(JSON.stringify({ progress: summary.processed, ...summary }));
        }
      }
    }
    await Promise.all(
      Array.from({ length: Math.min(concurrency, rows.length || 1) }, () => worker()),
    );
    console.log(JSON.stringify({ summary }));
    if (rows.length > 0) {
      console.log(`next start id: ${rows[rows.length - 1].id}`);
    }
    if (systemicError) {
      throw systemicError;
    }
    if (!options.apply) {
      console.log('dry-run only; pass --apply to upload/link homepage images');
      console.log('coverage target: every eligible blueprint should have homepage_image_url; pass --verify-coverage for counts');
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
