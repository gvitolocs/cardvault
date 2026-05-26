create table if not exists public.limitless_marketplace_expansions (
  expansion_key text primary key,
  pokoin_expansion_name text not null,
  pokoin_expansion_code text not null default '',
  normalized_pokoin_expansion_name text not null,
  limitless_expansion_name text not null,
  limitless_expansion_code text not null default '',
  normalized_limitless_expansion_name text not null,
  aliases text[] not null default '{}'::text[],
  raw_metadata jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  source_url text not null default '',
  source_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists limitless_marketplace_expansions_name_unique_idx
  on public.limitless_marketplace_expansions (
    normalized_pokoin_expansion_name,
    normalized_limitless_expansion_name
  );

create index if not exists limitless_marketplace_expansions_pokoin_code_idx
  on public.limitless_marketplace_expansions (lower(pokoin_expansion_code))
  where pokoin_expansion_code <> '';

create index if not exists limitless_marketplace_expansions_limitless_code_idx
  on public.limitless_marketplace_expansions (lower(limitless_expansion_code))
  where limitless_expansion_code <> '';

create index if not exists limitless_marketplace_expansions_aliases_idx
  on public.limitless_marketplace_expansions using gin (aliases);

create table if not exists public.limitless_marketplace_expansion_blueprints (
  expansion_key text not null references public.limitless_marketplace_expansions(expansion_key) on delete cascade,
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  card_id bigint generated always as (blueprint_id) stored,
  card_name text not null,
  collector_number text not null default '',
  normalized_collector_number text not null default '',
  set_code text not null default '',
  limitless_card_key text not null default '',
  limitless_card_name text not null default '',
  source_card_id text not null default '',
  source_url text not null default '',
  match_confidence numeric not null default 1 check (match_confidence >= 0 and match_confidence <= 1),
  match_reason text not null default '',
  raw_metadata jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  source_updated_at timestamptz,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (expansion_key, blueprint_id)
);

create index if not exists limitless_marketplace_expansion_blueprints_blueprint_idx
  on public.limitless_marketplace_expansion_blueprints (blueprint_id);

create index if not exists limitless_marketplace_expansion_blueprints_card_idx
  on public.limitless_marketplace_expansion_blueprints (card_id);

create index if not exists limitless_marketplace_expansion_blueprints_lookup_idx
  on public.limitless_marketplace_expansion_blueprints (
    lower(set_code),
    normalized_collector_number,
    lower(card_name)
  );

create index if not exists limitless_marketplace_expansion_blueprints_source_card_idx
  on public.limitless_marketplace_expansion_blueprints (source_card_id)
  where source_card_id <> '';
