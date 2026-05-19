#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const CLEANUP_SQL = path.join(
  ROOT_DIR,
  'supabase',
  'cleanup',
  '20260519_drop_marketplace_after_oracle_cutover.sql',
);

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

async function oracleLooksReady() {
  const pool = new Pool({
    connectionString: requireEnv('MARKETPLACE_DATABASE_URL'),
    max: 1,
    idleTimeoutMillis: 5_000,
    connectionTimeoutMillis: 8_000,
    ssl: { rejectUnauthorized: false },
  });
  try {
    const result = await pool.query(`
      select
        (select count(*)::integer from public.marketplace_search_candidates) as candidates,
        (select count(*)::integer from public.marketplace_card_versions) as versions
    `);
    const row = result.rows[0] || {};
    return Number(row.candidates) > 0 && Number(row.versions) > 0;
  } finally {
    await pool.end();
  }
}

async function runSupabaseCleanup() {
  const pool = new Pool({
    connectionString: requireEnv('SUPABASE_DB_URL'),
    max: 1,
    idleTimeoutMillis: 5_000,
    connectionTimeoutMillis: 8_000,
    ssl: { rejectUnauthorized: false },
  });
  try {
    const sql = fs.readFileSync(CLEANUP_SQL, 'utf8');
    await pool.query(sql);
  } finally {
    await pool.end();
  }
}

async function main() {
  if (process.env.CONFIRM_DROP_SUPABASE_MARKETPLACE !== 'drop-marketplace') {
    throw new Error(
      'Set CONFIRM_DROP_SUPABASE_MARKETPLACE=drop-marketplace to run destructive cleanup.',
    );
  }

  if (!(await oracleLooksReady())) {
    throw new Error(
      'Oracle marketplace database does not look ready; candidates and versions must both be non-empty.',
    );
  }

  await runSupabaseCleanup();
  console.log('Supabase marketplace/catalog/search objects dropped; forum objects kept.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
