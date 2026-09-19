#!/usr/bin/env node
try {
  const { config: loadEnv } = require('dotenv');
  loadEnv({ path: '.env.local', override: false, quiet: true });
  loadEnv({ path: '.env', override: false, quiet: true });
} catch {}
const { Pool } = require('pg');
const { meiliRequest } = require('../api/_meili_client');
const { meiliMarketplaceIndexName } = require('../api/_meili_marketplace');
const {
  MARKETPLACE_MEILI_SYNC_SELECT,
  mapMarketplaceMeiliDoc,
  meiliMarketplaceIndexSettings,
} = require('../api/_meili_document');

function marketplaceDatabaseUrl() {
  return process.env.MARKETPLACE_DATABASE_URL || '';
}

function deltaSinceIso() {
  const arg = process.argv.find((value) => value.startsWith('--since='));
  const value = arg ? arg.slice('--since='.length) : process.env.MEILI_DELTA_SINCE;
  if (!value) return new Date(Date.now() - 10 * 60 * 1000).toISOString();
  return new Date(value).toISOString();
}

async function main() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) throw new Error('MARKETPLACE_DATABASE_URL is required.');
  const since = deltaSinceIso();
  const ssl = /sslmode=disable/i.test(connectionString) ? false : { rejectUnauthorized: false };
  const pool = new Pool({ connectionString, ssl });
  const indexName = meiliMarketplaceIndexName();
  try {
    await meiliRequest(`/indexes/${encodeURIComponent(indexName)}/settings`, {
      method: 'PATCH',
      body: meiliMarketplaceIndexSettings(),
    });
  } catch (error) {
    if (error.statusCode !== 404) throw error;
  }
  const { rows } = await pool.query(
    `
    ${MARKETPLACE_MEILI_SYNC_SELECT}
    where coalesce(c.projected_at, c.imported_at, now()) >= $1::timestamptz
    order by c.card_id asc
    `,
    [since],
  );
  if (rows.length > 0) {
    await meiliRequest(`/indexes/${encodeURIComponent(indexName)}/documents`, {
      method: 'POST',
      body: rows.map(mapMarketplaceMeiliDoc),
    });
  }
  await pool.end();
  process.stdout.write(`delta sync complete since ${since}: ${rows.length} documents\n`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
