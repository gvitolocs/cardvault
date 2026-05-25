#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const { getFirebaseAdmin } = require('../api/_firebase');

const ROOT_DIR = path.resolve(__dirname, '..');
const DEFAULT_PAGE_SIZE = 1000;
const DEFAULT_BATCH_SIZE = 250;

function loadLocalEnv() {
  const envPath = path.join(ROOT_DIR, '.env.local');
  if (!fs.existsSync(envPath)) {
    return;
  }
  const content = fs.readFileSync(envPath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) {
      continue;
    }
    const separator = stripped.indexOf('=');
    const key = stripped
      .slice(0, separator)
      .replace(/^export\s+/, '')
      .trim();
    if (!key || process.env[key]) {
      continue;
    }
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function cleanEnvValue(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: Infinity,
    pageSize: DEFAULT_PAGE_SIZE,
    batchSize: DEFAULT_BATCH_SIZE,
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? Infinity : Number(raw);
    } else if (arg.startsWith('--page-size=')) {
      options.pageSize = Number(arg.slice('--page-size='.length));
    } else if (arg.startsWith('--batch-size=')) {
      options.batchSize = Number(arg.slice('--batch-size='.length));
    }
  }
  if (!Number.isFinite(options.limit) && options.limit !== Infinity) {
    throw new Error('--limit must be a number or all.');
  }
  if (!Number.isSafeInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 1000) {
    throw new Error('--page-size must be between 1 and 1000.');
  }
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 1000) {
    throw new Error('--batch-size must be between 1 and 1000.');
  }
  return options;
}

function createMarketplacePool() {
  if (!process.env.MARKETPLACE_DATABASE_URL) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  return new Pool({
    connectionString: process.env.MARKETPLACE_DATABASE_URL,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
  });
}

function timestampOrNull(value) {
  const text = String(value || '').trim();
  if (!text) {
    return null;
  }
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}

function userRow(authUser) {
  const providerIds = [...new Set((authUser.providerData || [])
    .map((provider) => String(provider.providerId || '').trim())
    .filter(Boolean))].sort();
  return {
    user_uid: String(authUser.uid || '').trim().slice(0, 128),
    email: String(authUser.email || '').trim().toLowerCase() || null,
    display_name: String(authUser.displayName || '').trim().slice(0, 160) || null,
    photo_url: String(authUser.photoURL || '').trim().slice(0, 1000) || null,
    disabled: Boolean(authUser.disabled),
    email_verified: Boolean(authUser.emailVerified),
    provider_ids: providerIds,
    firebase_created_at: timestampOrNull(authUser.metadata?.creationTime),
    firebase_last_sign_in_at: timestampOrNull(authUser.metadata?.lastSignInTime),
  };
}

function upsertFirebaseUsersSql(rowCount) {
  const columns = [
    'user_uid',
    'email',
    'display_name',
    'photo_url',
    'disabled',
    'email_verified',
    'provider_ids',
    'firebase_created_at',
    'firebase_last_sign_in_at',
  ];
  const rows = [];
  let parameter = 1;
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const placeholders = [];
    for (let columnIndex = 0; columnIndex < columns.length; columnIndex += 1) {
      placeholders.push(`$${parameter}`);
      parameter += 1;
    }
    rows.push(`(${placeholders.join(', ')})`);
  }
  return `
    insert into public.marketplace_firebase_users (${columns.join(', ')})
    values ${rows.join(', ')}
    on conflict (user_uid) do update set
      email = excluded.email,
      display_name = excluded.display_name,
      photo_url = excluded.photo_url,
      disabled = excluded.disabled,
      email_verified = excluded.email_verified,
      provider_ids = excluded.provider_ids,
      firebase_created_at = excluded.firebase_created_at,
      firebase_last_sign_in_at = excluded.firebase_last_sign_in_at,
      synced_at = now()
  `;
}

function upsertValues(rows) {
  return rows.flatMap((row) => [
    row.user_uid,
    row.email,
    row.display_name,
    row.photo_url,
    row.disabled,
    row.email_verified,
    row.provider_ids,
    row.firebase_created_at,
    row.firebase_last_sign_in_at,
  ]);
}

async function upsertRows(pool, rows, batchSize) {
  let upserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    await pool.query(upsertFirebaseUsersSql(batch.length), upsertValues(batch));
    upserted += batch.length;
  }
  return upserted;
}

async function listFirebaseUsers(auth, options, onRows) {
  let pageToken;
  let fetched = 0;
  let disabled = 0;
  let emailVerified = 0;
  do {
    const remaining = options.limit === Infinity ? options.pageSize : options.limit - fetched;
    if (remaining <= 0) {
      break;
    }
    const page = await auth.listUsers(Math.min(options.pageSize, remaining), pageToken);
    const rows = page.users
      .map(userRow)
      .filter((row) => row.user_uid);
    fetched += rows.length;
    disabled += rows.filter((row) => row.disabled).length;
    emailVerified += rows.filter((row) => row.email_verified).length;
    await onRows(rows);
    pageToken = page.pageToken;
  } while (pageToken);
  return { fetched, disabled, emailVerified };
}

async function syncFirebaseUsers({ admin, pool, options }) {
  const counts = {
    fetched: 0,
    upserted: 0,
    disabled: 0,
    emailVerified: 0,
    errors: 0,
  };
  const auth = admin.auth();
  try {
    const listed = await listFirebaseUsers(auth, options, async (rows) => {
      if (!options.apply) {
        return;
      }
      counts.upserted += await upsertRows(pool, rows, options.batchSize);
    });
    counts.fetched = listed.fetched;
    counts.disabled = listed.disabled;
    counts.emailVerified = listed.emailVerified;
  } catch (error) {
    counts.errors += 1;
    throw error;
  }
  return counts;
}

async function verifyOracle(pool) {
  const result = await pool.query(`
    select
      count(*)::integer as total_users,
      count(*) filter (where disabled)::integer as disabled_users,
      count(*) filter (where email_verified)::integer as email_verified_users,
      max(synced_at) as last_synced_at
    from public.marketplace_firebase_users
  `);
  return result.rows[0] || {};
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const admin = getFirebaseAdmin();
  const pool = options.apply ? createMarketplacePool() : null;
  try {
    const counts = await syncFirebaseUsers({ admin, pool, options });
    const result = {
      mode: options.apply ? 'apply' : 'dry-run',
      source: 'firebase-admin:listUsers',
      counts,
    };
    if (options.apply) {
      result.oracle = await verifyOracle(pool);
    }
    console.log(JSON.stringify(result, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply to upsert Firebase users into Oracle.');
    }
  } finally {
    await pool?.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  parseArgs,
  timestampOrNull,
  userRow,
  upsertFirebaseUsersSql,
  upsertValues,
};

