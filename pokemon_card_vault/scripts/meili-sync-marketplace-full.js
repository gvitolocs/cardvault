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

function batchSize() {
  const value = Number(process.env.MEILI_SYNC_BATCH_SIZE || 2000);
  return Math.min(Math.max(Math.trunc(value), 100), 5000);
}

async function ensureIndex(indexName) {
  try {
    await meiliRequest(`/indexes/${encodeURIComponent(indexName)}`);
  } catch (error) {
    if (error.statusCode !== 404) throw error;
    await meiliRequest('/indexes', {
      method: 'POST',
      body: { uid: indexName, primaryKey: 'doc_id' },
    });
  }
  await meiliRequest(`/indexes/${encodeURIComponent(indexName)}/settings`, {
    method: 'PATCH',
    body: meiliMarketplaceIndexSettings(),
  });
}

async function main() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  const ssl = /sslmode=disable/i.test(connectionString) ? false : { rejectUnauthorized: false };
  const pool = new Pool({ connectionString, ssl });
  const indexName = meiliMarketplaceIndexName();
  const size = batchSize();
  await ensureIndex(indexName);
  let lastCardId = 0;
  let total = 0;
  for (;;) {
    const { rows } = await pool.query(
      `
      ${MARKETPLACE_MEILI_SYNC_SELECT}
      where c.card_id > $1::bigint
      order by c.card_id asc
      limit $2::integer
      `,
      [lastCardId, size],
    );
    if (!rows.length) break;
    lastCardId = Number(rows[rows.length - 1].card_id);
    total += rows.length;
    await meiliRequest(`/indexes/${encodeURIComponent(indexName)}/documents`, {
      method: 'POST',
      body: rows.map(mapMarketplaceMeiliDoc),
    });
    process.stdout.write(`synced ${total} documents\n`);
  }
  await pool.end();
  process.stdout.write(`full sync complete: ${total} documents\n`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
