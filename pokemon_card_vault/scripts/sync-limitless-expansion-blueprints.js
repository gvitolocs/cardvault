#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadEnvFile(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) return false;
  for (const line of fs.readFileSync(resolved, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
  return true;
}

function parseArgs(argv) {
  const options = {
    apply: false,
    envFile: process.env.LIMITLESS_SYNC_ENV_FILE || DEFAULT_ENV_FILE,
    limit: 5000,
  };
  for (const arg of argv) {
    if (arg === '--apply') options.apply = true;
    else if (arg === '--dry-run') options.apply = false;
    else if (arg.startsWith('--env-file=')) options.envFile = arg.slice('--env-file='.length).trim();
    else if (arg.startsWith('--limit=')) options.limit = Number.parseInt(arg.slice('--limit='.length), 10);
    else throw new Error(`Unknown option: ${arg}`);
  }
  options.limit = Math.min(Math.max(Number.isSafeInteger(options.limit) ? options.limit : 5000, 1), 100000);
  return options;
}

function databaseUrl(env = process.env) {
  return String(env.MARKETPLACE_DATABASE_URL || env.MARKETPLACE_PEER4_DATABASE_URL || '').trim();
}

function createPool(env = process.env) {
  const connectionString = databaseUrl(env);
  if (!connectionString) throw new Error('MARKETPLACE_DATABASE_URL is required.');
  return new Pool({
    connectionString,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
    application_name: 'limitless-expansion-blueprint-sync',
  });
}

function normalizeText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function compactText(value) {
  return normalizeText(value).replace(/[^a-z0-9]/g, '');
}

function normalizeCollectorNumber(value) {
  const text = String(value || '').trim().toLowerCase();
  const match = text.match(/[a-z]*0*([0-9]+[a-z]?)(?=\s*(?:\/|$)|[^a-z0-9])/);
  return match ? match[1] : text.replace(/[^a-z0-9]+/g, '');
}

async function assertWritablePrimary(pool, apply) {
  const result = await pool.query('select pg_is_in_recovery() as in_recovery');
  if (apply && result.rows[0]?.in_recovery) {
    throw new Error('Refusing --apply because the configured marketplace database is in recovery/read-only mode.');
  }
}

async function readMappings(pool, limit) {
  const result = await pool.query(
    `
      with limitless_cards as (
        select
          deck_card.set_code,
          deck_card.collector_number,
          deck_card.card_name,
          deck_card.card_key,
          min(deck_card.source_url) as source_url,
          max(deck_card.updated_at) as source_updated_at,
          jsonb_agg(distinct deck_card.raw) filter (where deck_card.raw <> '{}'::jsonb) as raw_samples
        from public.limitless_public_decklist_cards deck_card
        where coalesce(deck_card.set_code, '') <> ''
          and coalesce(deck_card.collector_number, '') <> ''
          and coalesce(deck_card.card_name, '') <> ''
        group by deck_card.set_code, deck_card.collector_number, deck_card.card_name, deck_card.card_key
      )
      select
        limitless_cards.*,
        versions.card_id as blueprint_id,
        versions.name as pokoin_card_name,
        versions.expansion_name as pokoin_expansion_name,
        versions.expansion_number,
        expansions.code as pokoin_expansion_code
      from limitless_cards
      join lateral (
        select
          c.card_id,
          c.name,
          c.set_name as expansion_name,
          c.card_number as expansion_number
        from public.marketplace_search_candidates c
        left join public.cardtrader_pokemon_blueprints b on b.id = c.card_id
        cross join lateral (
          select
            regexp_replace(lower(coalesce(nullif(c.canonical_name, ''), c.name)), '[^a-z0-9]+', '', 'g') as candidate_name,
            regexp_replace(lower(limitless_cards.card_name), '[^a-z0-9]+', '', 'g') as limitless_name,
            regexp_replace(
              lower(coalesce(nullif(c.card_number, ''), nullif(b.version, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''))),
              '[^a-z0-9]+',
              '',
              'g'
            ) as candidate_number,
            regexp_replace(lower(limitless_cards.collector_number), '[^a-z0-9]+', '', 'g') as limitless_number,
            lower(coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', ''))) as candidate_set_code,
            lower(limitless_cards.set_code) as limitless_set_code
        ) normalized
        where c.item_kind = 'single'
          and normalized.candidate_name = normalized.limitless_name
          and (
            normalized.candidate_number = normalized.limitless_number
            or normalized.candidate_number like normalized.limitless_number || '%'
          )
          and (
            normalized.limitless_set_code = ''
            or normalized.candidate_set_code = normalized.limitless_set_code
          )
        order by c.search_weight desc, c.imported_at desc nulls last, c.card_id asc
        limit 1
      ) versions on true
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      order by versions.expansion_name asc, limitless_cards.set_code asc, limitless_cards.collector_number asc
      limit $1
    `,
    [limit],
  );
  return result.rows;
}

async function applyMappings(pool, rows) {
  let expansionCount = 0;
  let blueprintCount = 0;
  for (const row of rows) {
    const expansionName = row.pokoin_expansion_name || row.set_code;
    const expansionCode = String(row.pokoin_expansion_code || row.set_code || '').toUpperCase();
    const expansionKey = `${compactText(expansionName)}:${compactText(row.set_code || expansionCode)}`;
    await pool.query(
      `
        insert into public.limitless_marketplace_expansions (
          expansion_key,
          pokoin_expansion_name,
          pokoin_expansion_code,
          normalized_pokoin_expansion_name,
          limitless_expansion_name,
          limitless_expansion_code,
          normalized_limitless_expansion_name,
          aliases,
          raw_metadata,
          source,
          source_url,
          source_updated_at,
          updated_at
        ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,'limitless-public-decklists',$10,$11,now())
        on conflict (expansion_key) do update set
          pokoin_expansion_name = excluded.pokoin_expansion_name,
          pokoin_expansion_code = excluded.pokoin_expansion_code,
          normalized_pokoin_expansion_name = excluded.normalized_pokoin_expansion_name,
          limitless_expansion_name = excluded.limitless_expansion_name,
          limitless_expansion_code = excluded.limitless_expansion_code,
          normalized_limitless_expansion_name = excluded.normalized_limitless_expansion_name,
          aliases = excluded.aliases,
          raw_metadata = excluded.raw_metadata,
          source = excluded.source,
          source_url = excluded.source_url,
          source_updated_at = excluded.source_updated_at,
          updated_at = now()
      `,
      [
        expansionKey,
        expansionName,
        expansionCode,
        normalizeText(expansionName),
        expansionName,
        String(row.set_code || expansionCode).toUpperCase(),
        normalizeText(expansionName),
        [expansionName, expansionCode, String(row.set_code || '').toUpperCase()].filter(Boolean),
        { importSource: 'limitless_public_decklist_cards' },
        row.source_url || '',
        row.source_updated_at || null,
      ],
    );
    expansionCount += 1;

    await pool.query(
      `
        insert into public.limitless_marketplace_expansion_blueprints (
          expansion_key,
          blueprint_id,
          card_name,
          collector_number,
          normalized_collector_number,
          set_code,
          limitless_card_key,
          limitless_card_name,
          source_card_id,
          source_url,
          match_confidence,
          match_reason,
          raw_metadata,
          source,
          source_updated_at,
          updated_at
        ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,1,'exact_name_set_number',$11,'limitless-public-decklists',$12,now())
        on conflict (expansion_key, blueprint_id) do update set
          card_name = excluded.card_name,
          collector_number = excluded.collector_number,
          normalized_collector_number = excluded.normalized_collector_number,
          set_code = excluded.set_code,
          limitless_card_key = excluded.limitless_card_key,
          limitless_card_name = excluded.limitless_card_name,
          source_card_id = excluded.source_card_id,
          source_url = excluded.source_url,
          match_confidence = excluded.match_confidence,
          match_reason = excluded.match_reason,
          raw_metadata = excluded.raw_metadata,
          source = excluded.source,
          source_updated_at = excluded.source_updated_at,
          updated_at = now()
      `,
      [
        expansionKey,
        row.blueprint_id,
        row.pokoin_card_name || row.card_name,
        row.expansion_number || row.collector_number,
        normalizeCollectorNumber(row.expansion_number || row.collector_number),
        String(row.set_code || expansionCode).toUpperCase(),
        row.card_key || '',
        row.card_name || '',
        row.card_key || '',
        row.source_url || '',
        { rawSamples: row.raw_samples || [] },
        row.source_updated_at || null,
      ],
    );
    blueprintCount += 1;
  }
  return { expansionCount, blueprintCount };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  loadEnvFile(options.envFile);
  loadEnvFile(path.join(ROOT_DIR, '.env.local'));
  const pool = createPool();
  try {
    await assertWritablePrimary(pool, options.apply);
    const rows = await readMappings(pool, options.limit);
    if (!options.apply) {
      console.log(JSON.stringify({
        mode: 'dry-run',
        source: 'public.limitless_public_decklist_cards',
        matchedMappings: rows.length,
        sample: rows.slice(0, 10).map((row) => ({
          setCode: row.set_code,
          collectorNumber: row.collector_number,
          cardName: row.card_name,
          pokoinExpansionName: row.pokoin_expansion_name,
          blueprintId: String(row.blueprint_id || ''),
        })),
        note: 'This imports mappings from already-synced public Limitless decklist rows. A full Limitless card database API is not assumed.',
      }, null, 2));
      return;
    }
    const applied = await applyMappings(pool, rows);
    console.log(JSON.stringify({ mode: 'apply', matchedMappings: rows.length, ...applied }, null, 2));
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error && error.stack ? error.stack : error);
    process.exit(1);
  });
}

module.exports = {
  normalizeCollectorNumber,
  normalizeText,
  compactText,
  readMappings,
};
