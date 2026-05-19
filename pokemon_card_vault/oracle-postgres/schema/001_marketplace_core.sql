create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

create table if not exists public.cardtrader_pokemon_blueprints (
  id bigint primary key,
  name text not null,
  version text,
  game_id integer not null,
  category_id integer,
  expansion_id integer,
  image_url text,
  cardtrader_image_url text,
  cdn_image_url text,
  cdn_object_key text,
  preview_image_url text,
  preview_object_key text,
  card_palette jsonb not null default '{}'::jsonb,
  emoji text not null default '',
  card_market_ids jsonb,
  tcg_player_ids jsonb,
  editable_properties jsonb not null default '[]'::jsonb,
  blueprint jsonb not null,
  expansion jsonb,
  imported_at timestamptz not null default now()
);

create index if not exists cardtrader_pokemon_blueprints_expansion_id_idx
  on public.cardtrader_pokemon_blueprints (expansion_id);

create index if not exists cardtrader_pokemon_blueprints_name_trgm_idx
  on public.cardtrader_pokemon_blueprints using gin (name gin_trgm_ops);

create index if not exists cardtrader_pokemon_blueprints_name_idx
  on public.cardtrader_pokemon_blueprints (name);

alter table public.cardtrader_pokemon_blueprints
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.cardtrader_pokemon_blueprints
  add column if not exists emoji text not null default '';

create table if not exists public.cardtrader_pokemon_expansions (
  expansion_id integer,
  game_id integer not null default 5,
  code text,
  name text not null,
  normalized_name text primary key,
  compact_name text,
  name_tokens text[] not null default '{}'::text[],
  source_asset_code text,
  symbol_image_url text,
  symbol_object_key text,
  symbol_imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists cardtrader_pokemon_expansions_expansion_id_idx
  on public.cardtrader_pokemon_expansions (expansion_id);

create index if not exists cardtrader_pokemon_expansions_normalized_trgm_idx
  on public.cardtrader_pokemon_expansions using gin (normalized_name gin_trgm_ops);

create index if not exists cardtrader_pokemon_expansions_compact_trgm_idx
  on public.cardtrader_pokemon_expansions using gin (compact_name gin_trgm_ops);

create table if not exists public.marketplace_trainers (
  trainer_name text primary key,
  aliases text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_cards (
  card_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  name text not null,
  version text,
  product_variant text not null default '',
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  set_name text not null default 'Pokemon',
  rarity text not null default 'Card',
  card_type text not null default 'Trading card',
  card_number text not null default '',
  is_holo boolean not null default false,
  is_foil boolean not null default false,
  item_kind text not null default 'single' check (item_kind in ('single', 'product')),
  product_type text not null default 'card',
  trainer_name text not null default '',
  card_palette jsonb not null default '{}'::jsonb,
  emoji text not null default '',
  imported_at timestamptz,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_cards_imported_at_idx
  on public.marketplace_cards (imported_at desc nulls last);

create index if not exists marketplace_cards_name_trgm_idx
  on public.marketplace_cards using gin (name gin_trgm_ops);

create index if not exists marketplace_cards_name_idx
  on public.marketplace_cards (name);

create index if not exists marketplace_cards_item_kind_idx
  on public.marketplace_cards (item_kind, product_type, imported_at desc nulls last);

alter table public.marketplace_cards
  add column if not exists product_variant text not null default '';

alter table public.marketplace_cards
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_cards
  add column if not exists emoji text not null default '';

create table if not exists public.marketplace_card_events (
  id bigserial primary key,
  card_id bigint not null,
  event_type text not null check (
    event_type in ('view', 'search', 'click', 'reserve', 'cart_add', 'sale')
  ),
  weight numeric not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists marketplace_card_events_recent_idx
  on public.marketplace_card_events (occurred_at desc, card_id);

create index if not exists marketplace_card_events_card_recent_idx
  on public.marketplace_card_events (card_id, occurred_at desc);

create table if not exists public.marketplace_card_versions (
  card_id bigint primary key,
  name text not null,
  expansion_name text not null,
  expansion_number text not null,
  expansion_number_int integer,
  product_variant text not null default '',
  blueprint_id bigint,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  product_type text not null default 'card',
  trainer_name text not null default '',
  card_palette jsonb not null default '{}'::jsonb,
  emoji text not null default '',
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_card_versions_expansion_idx
  on public.marketplace_card_versions (expansion_name, expansion_number_int nulls last, expansion_number, card_id);

alter table public.marketplace_card_versions
  add column if not exists product_variant text not null default '';

alter table public.marketplace_card_versions
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_card_versions
  add column if not exists emoji text not null default '';

create table if not exists public.marketplace_search_candidates (
  card_id bigint primary key,
  name text not null,
  set_name text not null default 'Pokemon',
  card_number text not null default '',
  product_variant text not null default '',
  rarity text not null default 'Card',
  card_type text not null default 'Card',
  item_kind text not null default 'single' check (item_kind in ('single', 'product')),
  product_type text not null default 'card',
  trainer_name text not null default '',
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  card_palette jsonb not null default '{}'::jsonb,
  emoji text not null default '',
  search_text text not null default '',
  name_prefix text not null default '',
  set_prefix text not null default '',
  expansion_name text not null default '',
  search_weight numeric not null default 0,
  imported_at timestamptz,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_search_candidates_name_prefix_idx
  on public.marketplace_search_candidates (name_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_set_prefix_idx
  on public.marketplace_search_candidates (set_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_search_text_trgm_idx
  on public.marketplace_search_candidates using gin (search_text gin_trgm_ops);

alter table public.marketplace_search_candidates
  add column if not exists product_variant text not null default '';

alter table public.marketplace_search_candidates
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_search_candidates
  add column if not exists emoji text not null default '';

create index if not exists marketplace_search_candidates_expansion_name_idx
  on public.marketplace_search_candidates (expansion_name, search_weight desc);

create table if not exists public.marketplace_card_names (
  name text primary key,
  normalized_name text not null,
  compact_name text not null,
  emoji text not null default '',
  name_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_card_names_normalized_trgm_idx
  on public.marketplace_card_names using gin (normalized_name gin_trgm_ops);

alter table public.marketplace_card_names
  add column if not exists emoji text not null default '';

create table if not exists public.cards_type (
  type_key text primary key,
  label text not null,
  aliases text[] not null default '{}'::text[],
  palette_key text not null,
  sort_order integer not null default 1000,
  updated_at timestamptz not null default now()
);

create index if not exists cards_type_palette_key_idx
  on public.cards_type (palette_key, sort_order);

create table if not exists public.cards_name_type (
  name text not null references public.marketplace_card_names(name) on delete cascade,
  type_key text not null references public.cards_type(type_key) on delete cascade,
  priority integer not null default 100,
  source text not null default 'manual',
  updated_at timestamptz not null default now(),
  primary key (name, type_key)
);

create index if not exists cards_name_type_type_idx
  on public.cards_name_type (type_key, priority, name);

create index if not exists cards_name_type_lower_name_idx
  on public.cards_name_type (lower(name), priority);

create table if not exists public.marketplace_rarities (
  rarity text primary key,
  normalized_rarity text not null,
  compact_rarity text not null,
  rarity_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_expansion_numbers (
  card_number text primary key,
  number_int integer,
  normalized_number text not null,
  compact_number text not null,
  number_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_expansion_numbers_compact_idx
  on public.marketplace_expansion_numbers (compact_number);

create table if not exists public.marketplace_variations (
  variation_key text primary key,
  label text not null,
  aliases text[] not null default '{}'::text[],
  normalized_aliases text[] not null default '{}'::text[],
  compact_aliases text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_variations_compact_aliases_idx
  on public.marketplace_variations using gin (compact_aliases);

create table if not exists public.marketplace_expansion_aliases (
  alias text not null,
  normalized_alias text not null,
  compact_alias text not null,
  expansion_name text not null,
  normalized_expansion_name text not null,
  source text not null default 'manual',
  priority integer not null default 100,
  updated_at timestamptz not null default now(),
  primary key (normalized_alias, normalized_expansion_name)
);

create index if not exists marketplace_expansion_aliases_compact_idx
  on public.marketplace_expansion_aliases (compact_alias, priority, normalized_expansion_name);

create index if not exists marketplace_expansion_aliases_expansion_idx
  on public.marketplace_expansion_aliases (normalized_expansion_name, priority);

create table if not exists public.marketplace_card_variations (
  card_id bigint not null references public.marketplace_search_candidates(card_id) on delete cascade,
  variation_key text not null references public.marketplace_variations(variation_key) on delete cascade,
  label text not null,
  source_text text not null default '',
  updated_at timestamptz not null default now(),
  primary key (card_id, variation_key)
);

create index if not exists marketplace_card_variations_variation_idx
  on public.marketplace_card_variations (variation_key, card_id);

create table if not exists public.marketplace_cm_expansion_parsing (
  id bigserial primary key,
  expansion_name text not null,
  cardtrader_expansion_code text not null default '',
  cardmarket_locale text not null default 'en',
  cardmarket_expansion_slug text not null,
  cardmarket_set_code text not null default '',
  cardmarket_context_code text not null default '',
  number_format_rule text not null default 'unknown' check (
    number_format_rule in (
      'unknown',
      'name_only',
      'set_code_unpadded',
      'set_code_padded_2',
      'set_code_padded_3',
      'context_code',
      'manual'
    )
  ),
  applies_to_card_type text not null default '',
  confidence text not null default 'candidate' check (
    confidence in ('candidate', 'verified', 'manual', 'rejected')
  ),
  notes text not null default '',
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (expansion_name, cardmarket_locale, cardmarket_expansion_slug, applies_to_card_type)
);

create index if not exists marketplace_cm_expansion_parsing_expansion_idx
  on public.marketplace_cm_expansion_parsing (expansion_name, cardmarket_locale);

create index if not exists marketplace_cm_expansion_parsing_slug_idx
  on public.marketplace_cm_expansion_parsing (cardmarket_expansion_slug, cardmarket_locale);

create table if not exists public.marketplace_cm_product_parsing (
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  cardmarket_locale text not null default 'en',
  card_name text not null default '',
  cardmarket_name text not null default '',
  expansion_name text not null default '',
  cardmarket_expansion_slug text not null default '',
  collector_number text not null default '',
  normalized_collector_number text not null default '',
  cardmarket_set_code text not null default '',
  cardmarket_context_code text not null default '',
  cardmarket_variant_marker text not null default '',
  cardmarket_product_slug text not null,
  cardmarket_url text not null,
  match_status text not null default 'candidate' check (
    match_status in ('candidate', 'verified', 'manual', 'rejected')
  ),
  confidence text not null default 'candidate' check (
    confidence in ('candidate', 'verified', 'manual', 'rejected')
  ),
  verification_method text not null default '',
  verification_source text not null default '',
  notes text not null default '',
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (blueprint_id, cardmarket_locale)
);

create unique index if not exists marketplace_cm_product_parsing_url_idx
  on public.marketplace_cm_product_parsing (cardmarket_url);

create index if not exists marketplace_cm_product_parsing_expansion_idx
  on public.marketplace_cm_product_parsing (expansion_name, cardmarket_locale, match_status);

create index if not exists marketplace_cm_product_parsing_slug_idx
  on public.marketplace_cm_product_parsing (cardmarket_product_slug, cardmarket_locale);

