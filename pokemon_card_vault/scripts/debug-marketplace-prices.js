#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

function loadLocalEnv() {
  const envPath = path.resolve(__dirname, '..', '.env.local');
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
}

function createPool() {
  const connectionString = process.env.MARKETPLACE_DATABASE_URL;
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  const config = { connectionString };
  if (process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '0') {
    config.ssl = { rejectUnauthorized: false };
  }
  return new Pool(config);
}

function usage() {
  console.error('Usage: node scripts/debug-marketplace-prices.js <blueprint_id>');
}

async function main() {
  loadLocalEnv();
  const blueprintId = process.argv[2];
  if (!blueprintId) {
    usage();
    process.exit(1);
  }

  const pool = createPool();
  try {
    await pool.query('select public.refresh_marketplace_blueprint_price_summary($1)', [
      blueprintId,
    ]);

    const summary = await pool.query(
      `
        select *
        from public.marketplace_blueprint_price_summary
        where blueprint_id = $1::bigint
      `,
      [blueprintId],
    );
    const dimensions = await pool.query(
      `
        select
          condition,
          language,
          reverse,
          first_edition,
          foil_state,
          variant_state,
          sealed,
          signed,
          graded,
          grading_company,
          grade,
          active_listing_count,
          listed_quantity,
          lowest_ask_pkn,
          median_ask_pkn,
          average_ask_pkn,
          highest_ask_pkn,
          observation_count,
          last_observed_price_pkn,
          source_counts
        from public.marketplace_blueprint_price_table
        where blueprint_id = $1::bigint
        order by
          language,
          condition,
          reverse,
          first_edition,
          foil_state,
          graded,
          lowest_ask_pkn nulls last
      `,
      [blueprintId],
    );

    const checks = await pool.query(
      `
        select
          count(distinct condition) filter (where listed_quantity > 0) as active_conditions,
          count(*) filter (where reverse and listed_quantity > 0) as reverse_rows,
          count(*) filter (where not reverse and listed_quantity > 0) as standard_rows,
          count(*) filter (where graded and listed_quantity > 0) as graded_rows,
          count(*) filter (where first_edition and listed_quantity > 0) as first_edition_rows
        from public.marketplace_blueprint_price_table
        where blueprint_id = $1::bigint
      `,
      [blueprintId],
    );

    console.log(JSON.stringify(
      {
        blueprintId,
        summary: summary.rows[0] || null,
        checks: checks.rows[0] || {},
        dimensions: dimensions.rows,
      },
      null,
      2,
    ));
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
