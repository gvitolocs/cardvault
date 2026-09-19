-- APPLIED on pokoin-marketplace (2026-08-31).
-- Rename cardtrader_pokemon_expansions -> pokoin_pokemon_expansions (same pattern as 018 blueprints).
-- Backfill expansions present on pokoin_pokemon_blueprints but missing from the 553-row table
-- (CSV10C, MEGA Start Deck 100, Gem Packs, Simplified Chinese, Mega Evolution, ...).
-- Nationality is the print market of the SET (western / japanese / chinese), not listing language.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'cardtrader_pokemon_expansions'
      and c.relkind = 'r'
  ) and not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'pokoin_pokemon_expansions'
      and c.relkind = 'r'
  ) then
    alter table public.cardtrader_pokemon_expansions rename to pokoin_pokemon_expansions;
  end if;
end $$;

alter index if exists cardtrader_pokemon_expansions_pkey
  rename to pokoin_pokemon_expansions_pkey;
alter index if exists cardtrader_pokemon_expansions_expansion_id_idx
  rename to pokoin_pokemon_expansions_expansion_id_idx;
alter index if exists cardtrader_pokemon_expansions_normalized_trgm_idx
  rename to pokoin_pokemon_expansions_normalized_trgm_idx;
alter index if exists cardtrader_pokemon_expansions_compact_trgm_idx
  rename to pokoin_pokemon_expansions_compact_trgm_idx;

alter table public.pokoin_pokemon_expansions
  add column if not exists nationality text not null default 'unknown';

alter table public.pokoin_pokemon_expansions
  add column if not exists milo_gallery text not null default 'none';

alter table public.pokoin_pokemon_expansions
  drop constraint if exists pokoin_pokemon_expansions_nationality_check;

alter table public.pokoin_pokemon_expansions
  add constraint pokoin_pokemon_expansions_nationality_check
  check (nationality = any (array['western','japanese','chinese','korean','product','unknown']));

alter table public.pokoin_pokemon_expansions
  drop constraint if exists pokoin_pokemon_expansions_milo_gallery_check;

alter table public.pokoin_pokemon_expansions
  add constraint pokoin_pokemon_expansions_milo_gallery_check
  check (milo_gallery = any (array['western','japanese','chinese','none']));

create index if not exists pokoin_pokemon_expansions_nationality_idx
  on public.pokoin_pokemon_expansions (nationality, milo_gallery);

create or replace function public.pokoin_expansion_nationality(code text, name text)
returns text
language sql
immutable
as $fn$
  select case
    when coalesce(name, '') ~* 'korean' then 'korean'
    when coalesce(name, '') ~* 'thailand|indonesia' then 'unknown'
    when coalesce(name, '') ~* 'simplified chinese|traditional chinese|gem pack|^collect 151'
      or coalesce(code, '') ~* '^(cs[mv0-9]|csv|csm|cbb)'
      or lower(coalesce(code, '')) in ('151c', 'svp-c', '30thc')
      then 'chinese'
    when coalesce(name, '') ~* 'products?'
      or lower(coalesce(code, '')) in ('popr', 'svproducts', 'pkm-center', 'meproducts')
      then 'product'
    when lower(coalesce(code, '')) in (
        'sm-p', 's-p', 'mp-promo', 'sl', 'mc', 'pvs', 'ec1', 'xy', 'pxy',
        'dp-promos', 'svjp', 'svd', 'svc', 'svaw', 'svam', 'sval', 'svjl'
      )
      or coalesce(code, '') ~* '^(s[0-9]|sv[0-9]|sm[0-9]|m[0-9]|sp[0-9]|scjp|gym)'
      or coalesce(name, '') ~* 'movie commemoration|start deck 100|southern islands jp|constructed starter|half deck|battle master deck|battle strength deck'
      then 'japanese'
    else 'western'
  end;
$fn$;

create or replace function public.pokoin_expansion_milo_gallery(nationality text)
returns text
language sql
immutable
as $fn$
  select case nationality
    when 'western' then 'western'
    when 'japanese' then 'japanese'
    when 'chinese' then 'chinese'
    else 'none'
  end;
$fn$;

-- Every expansion_id on the latest blueprint download, including rows the
-- old 553-name table never received (search_candidates set_name upsert).
insert into public.pokoin_pokemon_expansions (
  expansion_id, game_id, code, name, normalized_name, compact_name, name_tokens,
  nationality, milo_gallery, updated_at
)
select
  src.expansion_id,
  coalesce(src.game_id, 5),
  coalesce(src.code, ''),
  src.name,
  public.marketplace_search_normalize(src.name),
  public.marketplace_search_compact(src.name),
  public.marketplace_search_tokenize(src.name),
  public.pokoin_expansion_nationality(src.code, src.name),
  public.pokoin_expansion_milo_gallery(public.pokoin_expansion_nationality(src.code, src.name)),
  now()
from (
  select
    b.expansion_id,
    max(b.game_id) as game_id,
    max(nullif(b.expansion->>'code', '')) as code,
    coalesce(
      max(nullif(b.expansion->>'name', '')),
      'Expansion ' || b.expansion_id::text
    ) as name
  from public.pokoin_pokemon_blueprints b
  where b.expansion_id is not null
  group by b.expansion_id
) src
where not exists (
  select 1
  from public.pokoin_pokemon_expansions e
  where e.expansion_id = src.expansion_id
)
on conflict (normalized_name) do nothing;

insert into public.pokoin_pokemon_expansions (
  expansion_id, game_id, code, name, normalized_name, compact_name, name_tokens,
  nationality, milo_gallery, updated_at
)
select
  src.expansion_id,
  coalesce(src.game_id, 5),
  coalesce(src.code, ''),
  src.name || ' [' || coalesce(src.code, src.expansion_id::text) || ']',
  public.marketplace_search_normalize(src.name || ' ' || coalesce(src.code, src.expansion_id::text)),
  public.marketplace_search_compact(src.name || ' ' || coalesce(src.code, src.expansion_id::text)),
  public.marketplace_search_tokenize(src.name || ' ' || coalesce(src.code, src.expansion_id::text)),
  public.pokoin_expansion_nationality(src.code, src.name),
  public.pokoin_expansion_milo_gallery(public.pokoin_expansion_nationality(src.code, src.name)),
  now()
from (
  select
    b.expansion_id,
    max(b.game_id) as game_id,
    max(nullif(b.expansion->>'code', '')) as code,
    coalesce(
      max(nullif(b.expansion->>'name', '')),
      'Expansion ' || b.expansion_id::text
    ) as name
  from public.pokoin_pokemon_blueprints b
  where b.expansion_id is not null
  group by b.expansion_id
) src
where not exists (
  select 1
  from public.pokoin_pokemon_expansions e
  where e.expansion_id = src.expansion_id
);

create unique index if not exists pokoin_pokemon_expansions_expansion_id_uidx
  on public.pokoin_pokemon_expansions (expansion_id)
  where expansion_id is not null;

update public.pokoin_pokemon_expansions
set
  nationality = public.pokoin_expansion_nationality(code, name),
  milo_gallery = public.pokoin_expansion_milo_gallery(public.pokoin_expansion_nationality(code, name)),
  updated_at = now()
where nationality is distinct from public.pokoin_expansion_nationality(code, name)
   or milo_gallery is distinct from public.pokoin_expansion_milo_gallery(public.pokoin_expansion_nationality(code, name));

-- Old name stays as an updatable view so the running Oracle API does not
-- 42P01 until the JS bundle is redeployed.
drop view if exists public.cardtrader_pokemon_expansions;
create view public.cardtrader_pokemon_expansions as
  select * from public.pokoin_pokemon_expansions;

commit;
