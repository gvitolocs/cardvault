#!/usr/bin/env node
try {
  const { config: loadEnv } = require('dotenv');
  loadEnv({ path: '.env.local', override: false, quiet: true });
  loadEnv({ path: '.env', override: false, quiet: true });
} catch {}
const { Pool } = require('pg');
const { meiliRequest } = require('../api/_meili_client');
const { meiliNameTokenIndexName } = require('../api/_meili_marketplace');

function marketplaceDatabaseUrl() {
  return process.env.MARKETPLACE_DATABASE_URL || '';
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
    body: {
      searchableAttributes: ['display_token', 'normalized_token', 'token_aliases'],
      filterableAttributes: ['language'],
      sortableAttributes: ['card_count'],
    },
  });
}

async function main() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) throw new Error('MARKETPLACE_DATABASE_URL is required.');
  const pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false } });
  const indexName = meiliNameTokenIndexName();
  await ensureIndex(indexName);
  const { rows } = await pool.query(
    `
    with base as (
      select
        c.name as display_token,
        public.marketplace_search_compact(c.name) as normalized_token,
        count(*)::integer as card_count,
        (array_agg(c.card_id order by c.search_weight desc, c.card_id asc))[1:24] as candidate_card_ids
      from public.marketplace_search_candidates c
      group by c.name, public.marketplace_search_compact(c.name)
    )
    select
      display_token,
      normalized_token,
      'en'::text as language,
      card_count,
      candidate_card_ids
    from base
    where normalized_token <> ''
    order by card_count desc, display_token asc
    `,
  );
  const documents = rows.map((row) => ({
    doc_id: `${row.language}_${row.normalized_token}`,
    display_token: row.display_token,
    normalized_token: row.normalized_token,
    token_aliases: [row.normalized_token],
    language: row.language,
    card_count: Number(row.card_count || 0),
    candidate_card_ids: Array.isArray(row.candidate_card_ids)
      ? row.candidate_card_ids.map((id) => String(id))
      : [],
  }));
  await meiliRequest(`/indexes/${encodeURIComponent(indexName)}/documents`, {
    method: 'POST',
    body: documents,
  });
  await pool.end();
  process.stdout.write(`name-token sync complete: ${documents.length} documents\n`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
