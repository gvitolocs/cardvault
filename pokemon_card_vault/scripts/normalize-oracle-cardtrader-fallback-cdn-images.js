const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');

const FALLBACK_URL = 'https://cardtrader.com/fallbacks/card_uploader/preview.png';
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_REPORT = 'workflows/reports/cardtrader-cdn-normalization-latest.json';

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
      let value = trimmed.slice(index + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
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
  const args = {
    apply: false,
    ids: [],
    limit: 25,
    report: DEFAULT_REPORT,
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      args.apply = true;
    } else if (arg.startsWith('--ids=')) {
      args.ids = arg
        .slice('--ids='.length)
        .split(',')
        .map((value) => value.trim())
        .filter((value) => /^\d+$/.test(value));
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      args.limit = raw === 'all' || raw === 'none' ? 0 : Number(raw);
    } else if (arg.startsWith('--report=')) {
      args.report = arg.slice('--report='.length).trim() || DEFAULT_REPORT;
    }
  }
  return args;
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

function fallbackKeyForRow(row) {
  const fields = [row.name, row.version, row.set_name].filter(Boolean).join(' ');
  const slug = slugify(fields) || `blueprint-${row.id}`;
  return `${row.id}_${slug}.png`;
}

async function downloadFallback() {
  const response = await fetch(FALLBACK_URL, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; Pokoin CDN normalizer)',
      Accept: 'image/png,image/*,*/*;q=0.8',
    },
  });
  if (!response.ok) {
    throw new Error(`Fallback download failed ${response.status}`);
  }
  const body = Buffer.from(await response.arrayBuffer());
  if (body.length < 256) {
    throw new Error(`Fallback download too small (${body.length} bytes)`);
  }
  return body;
}

async function fetchRows(pool, { ids, limit }) {
  const values = [];
  const where = [];
  if (ids.length > 0) {
    values.push(ids);
    where.push(`id = any($${values.length}::bigint[])`);
  } else {
    where.push(`
      (
        coalesce(image_url, '') like '%/fallbacks/card_uploader/preview.png%'
        or coalesce(cdn_image_url, '') like '%/fallbacks/card_uploader/preview.png%'
        or coalesce(cardtrader_image_url, '') like '%/fallbacks/card_uploader/preview.png%'
      )
    `);
  }
  const rowLimit = Number(limit) || 0;
  let limitSql = '';
  if (rowLimit > 0) {
    values.push(rowLimit);
    limitSql = `limit $${values.length}`;
  }
  const result = await pool.query(
    `
      select
        id,
        name,
        version,
        coalesce(nullif(expansion->>'name',''), nullif(blueprint->>'expansion_name',''), '') as set_name,
        image_url,
        cdn_image_url,
        cdn_object_key,
        preview_image_url,
        homepage_image_url,
        cardtrader_image_url,
        blueprint #>> '{image,url}' as blueprint_image_url,
        blueprint #>> '{image,preview,url}' as blueprint_preview_url
      from public.cardtrader_pokemon_blueprints
      where ${where.join(' and ')}
      order by id asc
      ${limitSql}
    `,
    values,
  );
  return result.rows;
}

async function updateRow(pool, row, cdnUrl, key) {
  await pool.query(
    `
      update public.cardtrader_pokemon_blueprints
      set
        image_url = coalesce(nullif(image_url, ''), $1),
        cdn_image_url = $1,
        cdn_object_key = $2,
        cardtrader_image_url = coalesce(nullif(cardtrader_image_url, ''), $3)
      where id = $4
    `,
    [cdnUrl, key, FALLBACK_URL, row.id],
  );
  for (const table of [
    'marketplace_cards',
    'marketplace_card_versions',
    'marketplace_search_candidates',
  ]) {
    await pool.query(
      `
        update public.${table}
        set image_url = $1, cdn_image_url = $1, projected_at = now()
        where card_id = $2
      `,
      [cdnUrl, row.id],
    );
  }
}

function rowNeedsServedCdn(row) {
  return [
    row.image_url,
    row.cdn_image_url,
  ].some((value) => String(value || '').includes('/fallbacks/card_uploader/preview.png'));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const localEnv = readEnv(path.resolve('.env.local'));
  const oracleEnv = readEnv(process.env.ORACLE_ENV_FILE || DEFAULT_ORACLE_ENV_FILE);
  const env = { ...localEnv, ...oracleEnv, ...process.env };
  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(/\/$/, '');

  const pool = new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });

  const report = {
    generated_at: new Date().toISOString(),
    mode: args.apply ? 'apply' : 'dry-run',
    source_url: FALLBACK_URL,
    importer_cause:
      'CardTrader raw blueprint/delta import preserved blueprint.image_url fallback preview.png as image_url/cardtrader_image_url on 2026-05-17 before CDN normalization guards existed.',
    counts: {
      scanned: 0,
      normalized: 0,
      sourceMetadataOnly: 0,
      skipped: 0,
      failed: 0,
    },
    samples: [],
  };

  try {
    const rows = await fetchRows(pool, args);
    report.counts.scanned = rows.length;
    const fallbackBody = args.apply ? await downloadFallback() : null;
    const client = args.apply
      ? new S3Client({
        region: 'auto',
        endpoint: `https://${required(env, 'CLOUDFLARE_ACCOUNT_ID')}.r2.cloudflarestorage.com`,
        credentials: {
          accessKeyId: required(env, 'R2_ACCESS_KEY_ID'),
          secretAccessKey: required(env, 'R2_SECRET_ACCESS_KEY'),
        },
      })
      : null;

    for (const row of rows) {
      const key = fallbackKeyForRow(row);
      const cdnUrl = `${cdnBase}/${key}`;
      const sample = {
        id: String(row.id),
        name: row.name,
        before: {
          image_url: row.image_url || '',
          cdn_image_url: row.cdn_image_url || '',
          cardtrader_image_url: row.cardtrader_image_url || '',
        },
        after: {
          image_url: cdnUrl,
          cdn_image_url: cdnUrl,
          cdn_object_key: key,
          cardtrader_image_url: row.cardtrader_image_url || FALLBACK_URL,
        },
      };

      const sourceMetadataOnly = !rowNeedsServedCdn(row);
      if (sourceMetadataOnly) {
        report.counts.sourceMetadataOnly += 1;
      }
      if (row.cdn_object_key === key && row.cdn_image_url === cdnUrl) {
        report.counts.skipped += 1;
        if (report.samples.length < 20) {
          report.samples.push({ ...sample, action: 'already-normalized' });
        }
        continue;
      }

      try {
        if (args.apply) {
          await client.send(new PutObjectCommand({
            Bucket: bucket,
            Key: key,
            Body: fallbackBody,
            ContentType: 'image/png',
            CacheControl: 'public, max-age=31536000, immutable',
          }));
          await updateRow(pool, row, cdnUrl, key);
        }
        report.counts.normalized += 1;
        if (report.samples.length < 20) {
          report.samples.push({
            ...sample,
            action: args.apply
              ? (sourceMetadataOnly ? 'normalized-source-metadata' : 'normalized-served-field')
              : (sourceMetadataOnly ? 'would-normalize-source-metadata' : 'would-normalize-served-field'),
          });
        }
      } catch (error) {
        report.counts.failed += 1;
        if (report.samples.length < 20) {
          report.samples.push({ ...sample, action: 'failed', error: error.message });
        }
      }
    }
  } finally {
    await pool.end();
  }

  fs.mkdirSync(path.dirname(args.report), { recursive: true });
  fs.writeFileSync(args.report, `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({
    report: args.report,
    mode: report.mode,
    counts: report.counts,
  }, null, 2));
  if (!args.apply) {
    console.log('dry-run only; pass --apply to upload normalized fallback objects and update Oracle projections');
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
