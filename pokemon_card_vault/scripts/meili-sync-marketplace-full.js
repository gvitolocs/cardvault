#!/usr/bin/env node
try {
  const { config: loadEnv } = require('dotenv');
  loadEnv({ path: '.env.local', override: false, quiet: true });
  loadEnv({ path: '.env', override: false, quiet: true });
} catch {}
const { Pool } = require('pg');
const { meiliRequest } = require('../api/_meili_client');
const { meiliMarketplaceIndexName } = require('../api/_meili_marketplace');

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
    body: {
      searchableAttributes: [
        'name',
        'name_normalized',
        'name_compact',
        'expansion_name',
        'expansion_aliases',
        'variation_tokens',
      ],
      filterableAttributes: ['language', 'card_id'],
      sortableAttributes: ['search_weight', 'updated_at_epoch'],
      typoTolerance: { enabled: true },
    },
  });
}

function mapRow(row) {
  return {
    doc_id: `${row.language}_${row.card_id}`,
    card_id: String(row.card_id),
    language: row.language || 'en',
    name: row.name || '',
    name_normalized: row.name_normalized || '',
    name_compact: row.name_compact || '',
    expansion_name: row.expansion_name || '',
    expansion_aliases: row.expansion_aliases || [],
    variation_tokens: row.variation_tokens || [],
    search_weight: Number(row.search_weight || 0),
    updated_at_epoch: Number(row.updated_at_epoch || 0),
  };
}

async function main() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  const pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false } });
  const indexName = meiliMarketplaceIndexName();
  const size = batchSize();
  await ensureIndex(indexName);
  let lastCardId = 0;
  let total = 0;
  for (;;) {
    const { rows } = await pool.query(
      `
      select
        c.card_id,
        'en'::text as language,
        c.name,
        public.marketplace_search_normalize(c.name) as name_normalized,
        public.marketplace_search_compact(c.name) as name_compact,
        c.expansion_name,
        coalesce((
          select array_agg(alias_rows.normalized_alias order by alias_rows.min_priority asc)
          from (
            select
              ea.normalized_alias,
              min(ea.priority) as min_priority
            from public.marketplace_expansion_aliases ea
            where ea.normalized_expansion_name = public.marketplace_search_normalize(c.expansion_name)
            group by ea.normalized_alias
          ) alias_rows
        ), '{}'::text[]) as expansion_aliases,
        coalesce(cv.variation_tokens, '{}'::text[]) as variation_tokens,
        c.search_weight,
        extract(epoch from coalesce(c.imported_at, now()))::bigint as updated_at_epoch
      from public.marketplace_search_candidates c
      left join lateral (
        select array_agg(distinct v.variation_key order by v.variation_key) as variation_tokens
        from public.marketplace_card_variations v
        where v.card_id = c.card_id
      ) cv on true
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
      body: rows.map(mapRow),
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
