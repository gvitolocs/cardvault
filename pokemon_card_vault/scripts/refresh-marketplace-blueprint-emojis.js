#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const [key, inlineValue] = token.slice(2).split('=', 2);
    if (inlineValue !== undefined) {
      args.set(key, inlineValue);
    } else if (argv[index + 1] && !argv[index + 1].startsWith('--')) {
      args.set(key, argv[index + 1]);
      index += 1;
    } else {
      args.set(key, true);
    }
  }
  return args;
}

function readEnv(filePath) {
  const values = {};
  if (!filePath || !fs.existsSync(filePath)) return values;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

function createPool(env) {
  if (env.MARKETPLACE_DATABASE_URL) {
    return new Pool({
      connectionString: env.MARKETPLACE_DATABASE_URL,
      ssl: { rejectUnauthorized: false },
      max: 2,
    });
  }
  for (const key of [
    'MARKETPLACE_DB_PUBLIC_HOST',
    'MARKETPLACE_DB_USER',
    'MARKETPLACE_DB_PASSWORD',
    'MARKETPLACE_DB_NAME',
  ]) {
    if (!env[key]) throw new Error(`Missing ${key}`);
  }
  return new Pool({
    host: env.MARKETPLACE_DB_PUBLIC_HOST,
    port: Number(env.MARKETPLACE_DB_PORT || 5432),
    database: env.MARKETPLACE_DB_NAME,
    user: env.MARKETPLACE_DB_USER,
    password: env.MARKETPLACE_DB_PASSWORD,
    ssl: { rejectUnauthorized: false },
    max: 2,
  });
}

async function withTransientEmojiFunctions(pool, callback) {
  await pool.query('begin');
  try {
    await applyEmojiFunctions(pool);
    const value = await callback();
    await pool.query('rollback');
    return value;
  } catch (error) {
    await pool.query('rollback');
    throw error;
  }
}

async function unresolvedBlueprints(pool, limit) {
  const result = await pool.query(
    `
      select
        b.id as blueprint_id,
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card') as rarity,
        coalesce(b.version, '') as product_variant,
        coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card') as card_type
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_blueprint_emojis e
        on e.blueprint_id = b.id
      where public.classify_marketplace_product_type(
          b.name,
          coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'),
          b.blueprint->>'category_name',
          b.blueprint->>'type',
          coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, b.id::text),
          b.version,
          b.id
        ) = 'card'
        and (e.blueprint_id is null or trim(e.emoji) = '' or position('🃏' in e.emoji) > 0)
      order by b.imported_at desc nulls last, b.id desc
      limit $1
    `,
    [limit],
  );
  return result.rows;
}

async function sampleComputedBlueprintEmojis(pool, limit) {
  const result = await pool.query(
    `
      select
        b.id::text as blueprint_id,
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card') as rarity,
        coalesce(b.version, '') as product_variant,
        public.marketplace_card_identity_emoji(
          coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          coalesce(b.version, '')
        ) as identity_emoji,
        public.marketplace_card_variant_emoji(
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          coalesce(b.version, '')
        ) as raw_rarity_variant_emoji,
        coalesce(
          nullif(public.marketplace_card_variant_emoji(
            b.name,
            coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
            coalesce(b.version, '')
          ), ''),
          public.marketplace_card_accent_emoji(
            coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
            b.name,
            coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
            coalesce(b.version, '')
          )
        ) as rarity_variant_emoji,
        public.marketplace_card_emoji(
          coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          coalesce(b.version, '')
        ) as emoji
      from public.cardtrader_pokemon_blueprints b
      where public.classify_marketplace_product_type(
          b.name,
          coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'),
          b.blueprint->>'category_name',
          b.blueprint->>'type',
          coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, b.id::text),
          b.version,
          b.id
        ) = 'card'
      order by random()
      limit ($1 * 4)
    `,
    [limit],
  );
  return result.rows.map((row) => {
    const tokens = String(row.emoji || '').trim().split(/\s+/).filter(Boolean);
    return {
      ...row,
      emoji: tokens.length === 3 ? row.emoji : 'UNRESOLVED',
      token_count: tokens.length,
    };
  }).filter((row) => row.emoji !== 'UNRESOLVED').slice(0, limit);
}

async function projectedDrift(pool) {
  const result = await pool.query(`
    select 'cardtrader_pokemon_blueprints' as table_name, count(*)::int as mismatches
    from public.cardtrader_pokemon_blueprints b
    join public.marketplace_blueprint_emojis e on e.blueprint_id = b.id
    where coalesce(b.emoji, '') <> e.emoji
    union all
    select 'marketplace_cards', count(*)::int
    from public.marketplace_cards c
    join public.marketplace_blueprint_emojis e on e.blueprint_id = c.card_id
    where coalesce(c.emoji, '') <> e.emoji
    union all
    select 'marketplace_search_candidates', count(*)::int
    from public.marketplace_search_candidates s
    join public.marketplace_blueprint_emojis e on e.blueprint_id = s.card_id
    where coalesce(s.emoji, '') <> e.emoji
    union all
    select 'marketplace_card_versions', count(*)::int
    from public.marketplace_card_versions v
    join public.marketplace_blueprint_emojis e on e.blueprint_id = v.card_id
    where coalesce(v.emoji, '') <> e.emoji
  `);
  return result.rows;
}

function emojiFunctionSql() {
  const schemaPath = path.join(__dirname, '../oracle-postgres/schema/002_marketplace_functions.sql');
  const schema = fs.readFileSync(schemaPath, 'utf8');
  const start = schema.indexOf('create or replace function public.marketplace_card_variant_emoji');
  const end = schema.indexOf('create or replace function public.refresh_marketplace_cards_from_blueprints');
  if (start === -1 || end === -1 || end <= start) {
    throw new Error('Unable to locate marketplace emoji function definitions in schema');
  }
  return schema.slice(start, end);
}

async function applyEmojiFunctions(pool) {
  await pool.query(emojiFunctionSql());
}

async function refreshBlueprintEmojisForIdRange(pool, minExclusiveId, maxInclusiveId) {
  const result = await pool.query(
    `
      insert into public.marketplace_blueprint_emojis (
        blueprint_id, name, rarity, product_variant,
        emoji_identity_a, emoji_identity_b, rarity_variant_emoji, emoji,
        source, reason, confidence, updated_at
      )
      select
        source.blueprint_id,
        source.name,
        source.rarity,
        source.product_variant,
        source.emoji_tokens[1],
        source.emoji_tokens[2],
        source.emoji_tokens[3],
        source.emoji,
        'projection-classifier',
        source.reason,
        0.75,
        now()
      from (
        select
          b.id as blueprint_id,
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card') as rarity,
          coalesce(b.version, '') as product_variant,
          regexp_split_to_array(public.marketplace_card_emoji(
            coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
            b.name,
            coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
            coalesce(b.version, '')
          ), '\\s+') as emoji_tokens,
          public.marketplace_card_emoji(
            coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
            b.name,
            coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
            coalesce(b.version, '')
          ) as emoji,
          'card-name-plus-rarity-variation classifier' as reason
        from public.cardtrader_pokemon_blueprints b
        where b.id > $1 and b.id <= $2
      ) source
      where array_length(source.emoji_tokens, 1) = 3
        and trim(source.emoji) <> ''
        and position('🃏' in source.emoji) = 0
      on conflict (blueprint_id) do update set
        name = excluded.name,
        rarity = excluded.rarity,
        product_variant = excluded.product_variant,
        emoji_identity_a = excluded.emoji_identity_a,
        emoji_identity_b = excluded.emoji_identity_b,
        rarity_variant_emoji = excluded.rarity_variant_emoji,
        emoji = excluded.emoji,
        reason = excluded.reason,
        confidence = excluded.confidence,
        updated_at = now()
      where public.marketplace_blueprint_emojis.source = 'projection-classifier'
    `,
    [minExclusiveId, maxInclusiveId],
  );
  return result.rowCount;
}

async function refreshAllBlueprintEmojisBatched(pool, batchSize) {
  await pool.query('select public.marketplace_seed_card_emoji_rules()');
  let lastId = 0;
  let totalRefreshed = 0;
  let batchIndex = 0;
  while (true) {
    const bounds = await pool.query(
      `
        select min(id)::bigint as min_id, max(id)::bigint as max_id, count(*)::int as row_count
        from (
          select id
          from public.cardtrader_pokemon_blueprints
          where id > $1
          order by id
          limit $2
        ) batch_ids
      `,
      [lastId, batchSize],
    );
    const { min_id: minId, max_id: maxId, row_count: rowCount } = bounds.rows[0] || {};
    if (!rowCount) {
      break;
    }
    batchIndex += 1;
    const refreshed = await refreshBlueprintEmojisForIdRange(pool, lastId, maxId);
    totalRefreshed += refreshed;
    lastId = maxId;
    console.log(
      `Batch ${batchIndex}: ids (${minId}-${maxId}] scanned=${rowCount} refreshed=${refreshed} total=${totalRefreshed}`,
    );
  }
  return totalRefreshed;
}

async function propagateSourceEmoji(pool) {
  await pool.query('set statement_timeout = 0');
  await pool.query('begin');
  try {
    const blueprints = await pool.query(`
      update public.cardtrader_pokemon_blueprints b
      set emoji = e.emoji
      from public.marketplace_blueprint_emojis e
      where e.blueprint_id = b.id
    `);
    const cards = await pool.query(`
      update public.marketplace_cards c
      set emoji = e.emoji, projected_at = now()
      from public.marketplace_blueprint_emojis e
      where e.blueprint_id = c.card_id
    `);
    const candidates = await pool.query(`
      update public.marketplace_search_candidates s
      set emoji = e.emoji, projected_at = now()
      from public.marketplace_blueprint_emojis e
      where e.blueprint_id = s.card_id
    `);
    const versions = await pool.query(`
      update public.marketplace_card_versions v
      set emoji = e.emoji, projected_at = now()
      from public.marketplace_blueprint_emojis e
      where e.blueprint_id = v.card_id
    `);
    await pool.query('commit');
    return {
      cardtraderPokemonBlueprints: blueprints.rowCount,
      marketplaceCards: cards.rowCount,
      marketplaceSearchCandidates: candidates.rowCount,
      marketplaceCardVersions: versions.rowCount,
    };
  } catch (error) {
    await pool.query('rollback');
    throw error;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const envPath = args.get('oracle-env') || process.env.MARKETPLACE_ORACLE_ENV_PATH || DEFAULT_ORACLE_ENV;
  const localEnvPath = path.join(__dirname, '../.env.local');
  const env = {
    ...readEnv(localEnvPath),
    ...readEnv(envPath),
    ...process.env,
  };
  const apply = args.has('apply');
  const refresh = args.has('refresh');
  const batched = args.has('batched');
  const sample = args.has('sample');
  const limit = Number(args.get('sample-size') || args.get('limit') || 50);
  const batchSize = Number(args.get('batch-size') || 2000);
  const pool = createPool(env);

  try {
    console.log(
      `Mode: ${apply ? 'apply' : 'dry-run'}${refresh ? ' + refresh' : ''}${batched ? ` + batched(batch-size=${batchSize})` : ''}`,
    );
    if (sample) {
      console.log(JSON.stringify(await withTransientEmojiFunctions(
        pool,
        () => sampleComputedBlueprintEmojis(pool, limit),
      ), null, 2));
      return;
    }
    if (apply) {
      await pool.query('set statement_timeout = 0');
      if (batched) {
        console.log('Applying emoji function definitions...');
        await applyEmojiFunctions(pool);
        const refreshed = await refreshAllBlueprintEmojisBatched(pool, batchSize);
        console.log(`Refreshed blueprint emoji source rows (batched): ${refreshed}`);
      } else {
        const result = await pool.query('select public.refresh_marketplace_blueprint_emojis() as refreshed');
        console.log(`Refreshed blueprint emoji source rows: ${result.rows[0]?.refreshed ?? 0}`);
      }
      if (refresh) {
        console.log('Propagated source emoji');
        console.log(JSON.stringify(await propagateSourceEmoji(pool), null, 2));
      }
    }

    const unresolved = await unresolvedBlueprints(pool, limit);
    console.log(`Unresolved single-card blueprint emoji rows: ${unresolved.length}${unresolved.length === limit ? '+' : ''}`);
    if (unresolved.length > 0) {
      console.table(unresolved.slice(0, limit));
    }

    console.log('Projected emoji drift');
    console.table(await projectedDrift(pool));
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
