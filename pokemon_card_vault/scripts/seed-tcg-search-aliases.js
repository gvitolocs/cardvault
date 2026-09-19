#!/usr/bin/env node
try {
  const { config: loadEnv } = require('dotenv');
  loadEnv({ path: '.env.local', override: false, quiet: true });
  loadEnv({ path: '.env', override: false, quiet: true });
} catch {}

const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { Pool } = require('pg');
const { parseTcgSearchAliasFile } = require('./lib/tcg-search-aliases');

const SOURCE = join(__dirname, '..', 'data', 'pokemon_tcg_expansion_shortnames_and_card_nicknames.txt');

function marketplaceDatabaseUrl() {
  return process.env.MARKETPLACE_DATABASE_URL
    || process.env.MARKETPLACE_POSTGRES_URL
    || '';
}

async function main() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  const parsed = parseTcgSearchAliasFile(readFileSync(SOURCE, 'utf8'));
  const ssl = /sslmode=disable/i.test(connectionString) ? false : { rejectUnauthorized: false };
  const pool = new Pool({ connectionString, ssl });
  const client = await pool.connect();
  const unmatched = [];
  try {
    await client.query('begin');
    await client.query('set local statement_timeout = 0');
    let aliasCount = 0;
    for (const row of parsed.expansionAliases) {
      const result = await client.query(
        `
        insert into public.marketplace_expansion_aliases (
          alias, normalized_alias, compact_alias,
          expansion_name, normalized_expansion_name,
          source, priority, updated_at
        )
        select
          $1,
          public.marketplace_search_normalize($1),
          public.marketplace_search_compact($1),
          $2,
          public.marketplace_search_normalize($2),
          'tcg_shortnames',
          $3::integer,
          now()
        where public.marketplace_search_normalize($1) <> ''
          and public.marketplace_search_normalize($2) <> ''
        on conflict (normalized_alias, normalized_expansion_name) do update set
          alias = excluded.alias,
          compact_alias = excluded.compact_alias,
          expansion_name = excluded.expansion_name,
          source = excluded.source,
          priority = least(public.marketplace_expansion_aliases.priority, excluded.priority),
          updated_at = now()
        `,
        [row.alias, row.expansionName, row.priority],
      );
      aliasCount += result.rowCount;
    }

    await client.query("delete from public.marketplace_card_nicknames where source = 'tcg_shortnames'");
    await client.query('delete from public.marketplace_card_nickname_hits');
    for (const row of parsed.cardNicknames) {
      await client.query(
        `
        insert into public.marketplace_card_nicknames (
          nickname, normalized_nickname, compact_nickname,
          card_name, expansion_name, card_number, notes, source, updated_at
        )
        values (
          $1,
          public.marketplace_search_normalize($1),
          public.marketplace_search_compact($1),
          $2, $3, $4, $5, 'tcg_shortnames', now()
        )
        on conflict (normalized_nickname, card_name, expansion_name, card_number) do update set
          nickname = excluded.nickname,
          compact_nickname = excluded.compact_nickname,
          notes = excluded.notes,
          updated_at = now()
        `,
        [row.nickname, row.cardName, row.expansionName, row.cardNumber || '', row.notes || ''],
      );
    }

    const nicknames = await client.query('select * from public.marketplace_card_nicknames where source = $1', ['tcg_shortnames']);
    let hitCount = 0;
    for (const row of nicknames.rows) {
      const hits = await client.query(
        `
        insert into public.marketplace_card_nickname_hits (card_id, nickname, updated_at)
        select c.card_id, $1, now()
        from public.marketplace_search_candidates c
        where coalesce(c.item_kind, 'single') = 'single'
          and replace(public.marketplace_search_compact(c.name), 'grey', 'gray')
            = replace(public.marketplace_search_compact($2), 'grey', 'gray')
          and (
            $4 <> ''
            or $3 = ''
            or public.marketplace_search_normalize(coalesce(c.expansion_name, c.set_name, ''))
               = public.marketplace_search_normalize($3)
            or public.marketplace_search_compact(coalesce(c.expansion_name, c.set_name, ''))
               = public.marketplace_search_compact($3)
            or public.marketplace_search_compact(c.expansion_name) like public.marketplace_search_compact($3) || '%'
            or public.marketplace_search_compact(c.set_name) like public.marketplace_search_compact($3) || '%'
            or (
              length(public.marketplace_search_compact($3)) >= 4
              and (
                public.marketplace_search_compact($3) like public.marketplace_search_compact(c.expansion_name) || '%'
                or public.marketplace_search_compact($3) like public.marketplace_search_compact(c.set_name) || '%'
              )
            )
            or exists (
              select 1
              from public.marketplace_expansion_aliases ea
              where ea.normalized_expansion_name = public.marketplace_search_normalize(c.expansion_name)
                and (
                  ea.normalized_alias = public.marketplace_search_normalize($3)
                  or ea.compact_alias = public.marketplace_search_compact($3)
                )
            )
          )
          and (
            $4 = ''
            or position(replace(lower($4), ' ', '') in replace(lower(c.card_number), ' ', '')) > 0
            or (
              public.marketplace_expansion_number_int(c.card_number)
                = public.marketplace_expansion_number_int($4)
              and public.marketplace_expansion_number_int($4) is not null
              and (
                $4 !~ '/'
                or replace(lower(c.card_number), ' ', '') ~ (
                  '(^|[^0-9])0*'
                  || nullif(ltrim(split_part(replace(lower($4), ' ', ''), '/', 1), '0'), '')
                  || '/0*'
                  || coalesce(nullif(ltrim(split_part(replace(lower($4), ' ', ''), '/', 2), '0'), ''), '[a-z0-9-]+')
                )
              )
            )
          )
        on conflict (card_id, nickname) do update set updated_at = now()
        returning card_id
        `,
        [row.nickname, row.card_name, row.expansion_name || '', row.card_number || ''],
      );
      hitCount += hits.rowCount;
      if (!hits.rowCount) {
        unmatched.push(`${row.nickname} → ${row.card_name} / ${row.expansion_name} / ${row.card_number}`);
      }
    }
    await client.query('commit');
    process.stdout.write(JSON.stringify({
      expansionAliases: parsed.expansionAliases.length,
      aliasUpserts: aliasCount,
      cardNicknames: parsed.cardNicknames.length,
      nicknameHits: hitCount,
      unmatched,
    }, null, 2) + '\n');
  } catch (error) {
    await client.query('rollback');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
