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
  homepage_image_url text,
  homepage_object_key text,
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

create table if not exists public.marketplace_blueprint_artists (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  card_id bigint generated always as (blueprint_id) stored,
  artist text not null,
  illustrator text not null,
  normalized_artist text not null,
  source text not null,
  source_card_id text not null default '',
  source_url text not null default '',
  confidence numeric not null default 0 check (confidence >= 0 and confidence <= 1),
  match_reason text not null default '',
  matched_at timestamptz not null default now(),
  raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_blueprint_artists_card_idx
  on public.marketplace_blueprint_artists (card_id);

create index if not exists marketplace_blueprint_artists_normalized_artist_idx
  on public.marketplace_blueprint_artists (normalized_artist);

create index if not exists marketplace_blueprint_artists_source_idx
  on public.marketplace_blueprint_artists (source, matched_at desc);

alter table public.marketplace_blueprint_artists
  add column if not exists artist_card_count integer not null default 0;

create index if not exists marketplace_blueprint_artists_count_idx
  on public.marketplace_blueprint_artists (normalized_artist, artist_card_count desc);

create table if not exists public.marketplace_artist_profiles (
  normalized_artist text primary key,
  display_name text not null default '',
  summary text not null default '',
  bio text not null default '',
  profile_image_url text not null default '',
  profile_image_cdn_url text not null default '',
  profile_image_object_key text not null default '',
  pocketmonsters_url text not null default '',
  pocketmonsters_id text not null default '',
  bulbapedia_url text not null default '',
  bulbapedia_title text not null default '',
  source_name text not null default '',
  source_url text not null default '',
  source_attribution jsonb not null default '{}'::jsonb,
  fetched_at timestamptz,
  raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.marketplace_artist_profiles
  add column if not exists summary text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists profile_image_cdn_url text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists profile_image_object_key text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists pocketmonsters_url text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists pocketmonsters_id text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists bulbapedia_url text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists bulbapedia_title text not null default '';

alter table public.marketplace_artist_profiles
  add column if not exists source_attribution jsonb not null default '{}'::jsonb;

alter table public.marketplace_artist_profiles
  add column if not exists fetched_at timestamptz;

create index if not exists marketplace_artist_profiles_updated_idx
  on public.marketplace_artist_profiles (updated_at desc);

create index if not exists marketplace_artist_profiles_pocketmonsters_idx
  on public.marketplace_artist_profiles (pocketmonsters_id)
  where pocketmonsters_id <> '';

create index if not exists marketplace_artist_profiles_bulbapedia_idx
  on public.marketplace_artist_profiles (bulbapedia_title)
  where bulbapedia_title <> '';

create table if not exists public.marketplace_blueprint_tcg_metadata (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  card_id bigint generated always as (blueprint_id) stored,
  category text not null default '',
  set_id text not null default '',
  set_name text not null default '',
  set_logo_url text not null default '',
  set_symbol_url text not null default '',
  set_official_card_count integer,
  set_total_card_count integer,
  set_metadata jsonb not null default '{}'::jsonb,
  variants jsonb not null default '{}'::jsonb,
  types jsonb not null default '[]'::jsonb,
  hp integer,
  stage text not null default '',
  evolve_from text not null default '',
  attacks jsonb not null default '[]'::jsonb,
  abilities jsonb not null default '[]'::jsonb,
  weaknesses jsonb not null default '[]'::jsonb,
  resistances jsonb not null default '[]'::jsonb,
  retreat integer,
  description text not null default '',
  flavor_text text not null default '',
  regulation_mark text not null default '',
  legal jsonb not null default '{}'::jsonb,
  source text not null default 'tcgdex',
  source_card_id text not null default '',
  source_url text not null default '',
  confidence numeric not null default 0 check (confidence >= 0 and confidence <= 1),
  match_reason text not null default '',
  matched_at timestamptz not null default now(),
  source_updated_at timestamptz,
  raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_blueprint_tcg_metadata_card_idx
  on public.marketplace_blueprint_tcg_metadata (card_id);

create index if not exists marketplace_blueprint_tcg_metadata_category_idx
  on public.marketplace_blueprint_tcg_metadata (category);

create index if not exists marketplace_blueprint_tcg_metadata_regulation_mark_idx
  on public.marketplace_blueprint_tcg_metadata (regulation_mark);

create index if not exists marketplace_blueprint_tcg_metadata_source_updated_idx
  on public.marketplace_blueprint_tcg_metadata (source, source_updated_at desc nulls last, matched_at desc);

create index if not exists marketplace_blueprint_tcg_metadata_set_idx
  on public.marketplace_blueprint_tcg_metadata (set_id, set_name);

create index if not exists marketplace_blueprint_tcg_metadata_types_gin_idx
  on public.marketplace_blueprint_tcg_metadata using gin (types);

create index if not exists marketplace_blueprint_tcg_metadata_legal_gin_idx
  on public.marketplace_blueprint_tcg_metadata using gin (legal);

create table if not exists public.marketplace_blueprint_classification_overrides (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  item_kind text not null default 'single' check (item_kind in ('single', 'product')),
  product_type text not null default 'card',
  source text not null default '',
  reason text not null default '',
  debug_uid text not null default '',
  debug_email text not null default '',
  debug_username text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_blueprint_classification_overrides_source_idx
  on public.marketplace_blueprint_classification_overrides (source, updated_at desc);

create table if not exists public.marketplace_artist_debug_skips (
  id bigserial primary key,
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  debug_uid text not null default '',
  debug_email text not null default '',
  debug_username text not null default '',
  reason text not null default '',
  skipped_at timestamptz not null default now()
);

create index if not exists marketplace_artist_debug_skips_recent_idx
  on public.marketplace_artist_debug_skips (blueprint_id, debug_uid, debug_email, skipped_at desc);

alter table public.cardtrader_pokemon_blueprints
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.cardtrader_pokemon_blueprints
  add column if not exists emoji text not null default '';

alter table public.cardtrader_pokemon_blueprints
  add column if not exists homepage_image_url text;

alter table public.cardtrader_pokemon_blueprints
  add column if not exists homepage_object_key text;

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
  logo_image_url text,
  logo_object_key text,
  logo_imported_at timestamptz,
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
  source_name text not null default '',
  display_name text not null default '',
  canonical_name text not null default '',
  version text,
  product_variant text not null default '',
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  homepage_image_url text,
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
  add column if not exists source_name text not null default '';

alter table public.marketplace_cards
  add column if not exists display_name text not null default '';

alter table public.marketplace_cards
  add column if not exists canonical_name text not null default '';

alter table public.marketplace_cards
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_cards
  add column if not exists emoji text not null default '';

alter table public.marketplace_cards
  add column if not exists homepage_image_url text;

create table if not exists public.marketplace_card_events (
  id bigserial primary key,
  card_id bigint not null,
  user_uid text,
  event_type text not null check (
    event_type in ('view', 'search', 'click', 'reserve', 'cart_add', 'sale')
  ),
  weight numeric not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

alter table public.marketplace_card_events
  add column if not exists user_uid text;

create index if not exists marketplace_card_events_recent_idx
  on public.marketplace_card_events (occurred_at desc, card_id);

create index if not exists marketplace_card_events_card_recent_idx
  on public.marketplace_card_events (card_id, occurred_at desc);

create index if not exists marketplace_card_events_user_recent_idx
  on public.marketplace_card_events (user_uid, occurred_at desc, card_id)
  where user_uid is not null;

create table if not exists public.marketplace_card_watchlist_analytics (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  watchlist_count integer not null default 0 check (watchlist_count >= 0),
  first_watchlisted_at timestamptz,
  last_watchlisted_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.marketplace_card_watchlist_analytics
  add column if not exists first_watchlisted_at timestamptz;

alter table public.marketplace_card_watchlist_analytics
  add column if not exists last_watchlisted_at timestamptz;

create index if not exists marketplace_card_watchlist_analytics_count_idx
  on public.marketplace_card_watchlist_analytics (watchlist_count desc, updated_at desc);

create table if not exists public.marketplace_card_watchlist_users (
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  user_uid text not null,
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (blueprint_id, user_uid)
);

create index if not exists marketplace_card_watchlist_users_user_idx
  on public.marketplace_card_watchlist_users (user_uid, updated_at desc);

create table if not exists public.marketplace_card_cart_analytics (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  cart_holder_count integer not null default 0 check (cart_holder_count >= 0),
  first_added_at timestamptz,
  last_added_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.marketplace_card_cart_analytics
  add column if not exists first_added_at timestamptz;

alter table public.marketplace_card_cart_analytics
  add column if not exists last_added_at timestamptz;

create index if not exists marketplace_card_cart_analytics_count_idx
  on public.marketplace_card_cart_analytics (cart_holder_count desc, updated_at desc);

create table if not exists public.marketplace_card_cart_users (
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  holder_key text not null,
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (blueprint_id, holder_key)
);

create index if not exists marketplace_card_cart_users_holder_idx
  on public.marketplace_card_cart_users (holder_key, updated_at desc);

create table if not exists public.marketplace_user_listings (
  id uuid primary key default gen_random_uuid(),
  card_id text not null,
  seller_uid text not null,
  seller_name text not null default 'Pokoin seller',
  seller_country text not null default 'EU',
  seller_reputation_label text not null default 'New',
  condition text not null default 'NM',
  language text not null default 'EN',
  price_pkn numeric not null check (price_pkn > 0),
  quantity_available integer not null default 1 check (quantity_available >= 0 and quantity_available <= 999999),
  signed boolean not null default false,
  reverse boolean not null default false,
  first_edition boolean not null default false,
  foil_state text not null default 'standard',
  variant_state text not null default '',
  sealed boolean not null default false,
  graded boolean not null default false,
  grading_company text,
  grade text,
  certification_id text,
  shipping_available boolean not null default true,
  reserve_available boolean not null default false,
  nft_available boolean not null default false,
  seller_comment text not null default '',
  source text not null default 'pokoin_user_listing',
  source_listing_id text not null default '',
  status text not null default 'active' check (status in ('active', 'paused', 'inactive', 'sold_out')),
  card_name text not null default '',
  card_image_url text not null default '',
  set_name text not null default '',
  collector_number text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.marketplace_user_listings
  alter column reverse set default false;

alter table public.marketplace_user_listings
  add column if not exists sealed boolean not null default false;

alter table public.marketplace_user_listings
  add column if not exists seller_comment text not null default '';

alter table public.marketplace_user_listings
  add column if not exists first_edition boolean not null default false;

alter table public.marketplace_user_listings
  add column if not exists foil_state text not null default 'standard';

alter table public.marketplace_user_listings
  add column if not exists variant_state text not null default '';

alter table public.marketplace_user_listings
  add column if not exists reserve_available boolean not null default false;

alter table public.marketplace_user_listings
  add column if not exists source text not null default 'pokoin_user_listing';

alter table public.marketplace_user_listings
  add column if not exists source_listing_id text not null default '';

create index if not exists marketplace_user_listings_active_card_idx
  on public.marketplace_user_listings (card_id, status, price_pkn, created_at desc);

create index if not exists marketplace_user_listings_price_dimensions_idx
  on public.marketplace_user_listings (
    card_id, status, condition, language, reverse, first_edition, foil_state,
    sealed, signed, graded, grading_company, grade, price_pkn
  );

create index if not exists marketplace_user_listings_seller_idx
  on public.marketplace_user_listings (seller_uid, updated_at desc);

create index if not exists marketplace_user_listings_status_idx
  on public.marketplace_user_listings (status, updated_at desc);

create table if not exists public.marketplace_price_observations (
  id uuid primary key default gen_random_uuid(),
  blueprint_id bigint not null,
  source text not null default 'pokoin_user_listing',
  source_item_id text not null default '',
  observed_at timestamptz not null default now(),
  currency text not null default 'PKN',
  price numeric not null check (price > 0),
  price_pkn numeric not null check (price_pkn > 0),
  quantity integer not null default 1 check (quantity >= 0),
  condition text not null default 'NM',
  language text not null default 'EN',
  reverse boolean not null default false,
  first_edition boolean not null default false,
  foil_state text not null default 'standard',
  variant_state text not null default '',
  sealed boolean not null default false,
  signed boolean not null default false,
  graded boolean not null default false,
  grading_company text,
  grade text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists marketplace_price_observations_blueprint_idx
  on public.marketplace_price_observations (blueprint_id, observed_at desc);

create index if not exists marketplace_price_observations_dimensions_idx
  on public.marketplace_price_observations (
    blueprint_id, source, condition, language, reverse, first_edition,
    foil_state, sealed, signed, graded, grading_company, grade, observed_at desc
  );

create table if not exists public.marketplace_blueprint_price_table (
  blueprint_id bigint not null,
  condition text not null default 'NM',
  language text not null default 'EN',
  reverse boolean not null default false,
  first_edition boolean not null default false,
  foil_state text not null default 'standard',
  variant_state text not null default '',
  sealed boolean not null default false,
  signed boolean not null default false,
  graded boolean not null default false,
  grading_company text not null default '',
  grade text not null default '',
  active_listing_count integer not null default 0,
  listed_quantity integer not null default 0,
  lowest_ask_pkn numeric,
  highest_ask_pkn numeric,
  average_ask_pkn numeric,
  median_ask_pkn numeric,
  observation_count integer not null default 0,
  last_observed_price_pkn numeric,
  source_counts jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now(),
  primary key (
    blueprint_id, condition, language, reverse, first_edition, foil_state,
    variant_state, sealed, signed, graded, grading_company, grade
  )
);

create index if not exists marketplace_blueprint_price_table_lowest_idx
  on public.marketplace_blueprint_price_table (blueprint_id, lowest_ask_pkn);

create table if not exists public.marketplace_blueprint_price_summary (
  blueprint_id bigint primary key,
  listed_quantity integer not null default 0,
  active_listing_count integer not null default 0,
  lowest_ask_pkn numeric,
  median_ask_pkn numeric,
  average_ask_pkn numeric,
  highest_ask_pkn numeric,
  observation_count integer not null default 0,
  last_observed_price_pkn numeric,
  source_counts jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);

create table if not exists public.marketplace_hot_blueprints (
  blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  name text not null,
  set_name text not null default 'Pokemon',
  card_number text not null default '',
  rarity text not null default 'Card',
  card_type text not null default 'Card',
  item_kind text not null default 'single',
  product_type text not null default 'card',
  views_1h integer not null default 0,
  searches_1h integer not null default 0,
  clicks_1h integer not null default 0,
  cart_adds_1h integer not null default 0,
  reserves_1h integer not null default 0,
  sales_1h integer not null default 0,
  hot_score_1h numeric not null default 0,
  views_24h integer not null default 0,
  searches_24h integer not null default 0,
  clicks_24h integer not null default 0,
  cart_adds_24h integer not null default 0,
  reserves_24h integer not null default 0,
  sales_24h integer not null default 0,
  hot_score_24h numeric not null default 0,
  views_7d integer not null default 0,
  searches_7d integer not null default 0,
  clicks_7d integer not null default 0,
  cart_adds_7d integer not null default 0,
  reserves_7d integer not null default 0,
  sales_7d integer not null default 0,
  hot_score_7d numeric not null default 0,
  last_event_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);

create index if not exists marketplace_hot_blueprints_score_24h_idx
  on public.marketplace_hot_blueprints (hot_score_24h desc, last_event_at desc nulls last);

create index if not exists marketplace_hot_blueprints_score_1h_idx
  on public.marketplace_hot_blueprints (hot_score_1h desc, last_event_at desc nulls last);

create table if not exists public.cardtrader_blueprint_daily_analytics (
  observed_day date not null,
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  listing_count integer not null default 0,
  listed_quantity integer not null default 0,
  seller_count integer not null default 0,
  sold_count integer not null default 0,
  sold_quantity integer not null default 0,
  min_price_pkn numeric,
  median_price_pkn numeric,
  average_price_pkn numeric,
  max_price_pkn numeric,
  previous_min_price_pkn numeric,
  price_change_pct numeric,
  sell_through_rate numeric not null default 0,
  source_counts jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now(),
  primary key (observed_day, blueprint_id)
);

create index if not exists cardtrader_blueprint_daily_analytics_blueprint_day_idx
  on public.cardtrader_blueprint_daily_analytics (blueprint_id, observed_day desc);

create index if not exists cardtrader_blueprint_daily_analytics_hot_idx
  on public.cardtrader_blueprint_daily_analytics (
    observed_day desc,
    sold_count desc,
    listed_quantity desc,
    sell_through_rate desc
  );

create table if not exists public.marketplace_card_versions (
  card_id bigint primary key,
  name text not null,
  source_name text not null default '',
  display_name text not null default '',
  canonical_name text not null default '',
  expansion_name text not null,
  expansion_number text not null,
  expansion_number_int integer,
  product_variant text not null default '',
  blueprint_id bigint,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  homepage_image_url text,
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
  add column if not exists source_name text not null default '';

alter table public.marketplace_card_versions
  add column if not exists display_name text not null default '';

alter table public.marketplace_card_versions
  add column if not exists canonical_name text not null default '';

alter table public.marketplace_card_versions
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_card_versions
  add column if not exists emoji text not null default '';

alter table public.marketplace_card_versions
  add column if not exists homepage_image_url text;

create table if not exists public.marketplace_search_candidates (
  card_id bigint primary key,
  name text not null,
  source_name text not null default '',
  display_name text not null default '',
  canonical_name text not null default '',
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
  homepage_image_url text,
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
  add column if not exists source_name text not null default '';

alter table public.marketplace_search_candidates
  add column if not exists display_name text not null default '';

alter table public.marketplace_search_candidates
  add column if not exists canonical_name text not null default '';

alter table public.marketplace_search_candidates
  add column if not exists card_palette jsonb not null default '{}'::jsonb;

alter table public.marketplace_search_candidates
  add column if not exists emoji text not null default '';

alter table public.marketplace_search_candidates
  add column if not exists homepage_image_url text;

create index if not exists marketplace_search_candidates_expansion_name_idx
  on public.marketplace_search_candidates (expansion_name, search_weight desc);

create table if not exists public.marketplace_card_urls (
  card_id bigint primary key references public.marketplace_search_candidates(card_id) on delete cascade,
  language text not null default 'en',
  canonical_slug text not null check (canonical_slug <> ''),
  canonical_slug_normalized text not null check (canonical_slug_normalized <> ''),
  canonical_path text not null check (canonical_path <> ''),
  canonical_path_normalized text not null check (canonical_path_normalized <> ''),
  rarity text not null default 'Card',
  name text not null,
  card_number text not null default '',
  set_name text not null default 'Pokemon',
  item_kind text not null default 'single',
  product_type text not null default 'card',
  is_unique boolean not null default true,
  duplicate_group_size integer not null default 1 check (duplicate_group_size >= 1),
  duplicate_keys jsonb not null default '[]'::jsonb,
  source_projected_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.marketplace_card_urls
  add column if not exists language text not null default 'en';

alter table public.marketplace_card_urls
  add column if not exists canonical_slug_normalized text not null default '';

alter table public.marketplace_card_urls
  add column if not exists canonical_path_normalized text not null default '';

alter table public.marketplace_card_urls
  add column if not exists item_kind text not null default 'single';

alter table public.marketplace_card_urls
  add column if not exists product_type text not null default 'card';

alter table public.marketplace_card_urls
  add column if not exists is_unique boolean not null default true;

alter table public.marketplace_card_urls
  add column if not exists duplicate_group_size integer not null default 1;

alter table public.marketplace_card_urls
  add column if not exists duplicate_keys jsonb not null default '[]'::jsonb;

alter table public.marketplace_card_urls
  add column if not exists source_projected_at timestamptz;

drop index if exists public.marketplace_card_urls_language_slug_idx;
drop index if exists public.marketplace_card_urls_language_slug_normalized_idx;
drop index if exists public.marketplace_card_urls_canonical_path_idx;
drop index if exists public.marketplace_card_urls_canonical_path_normalized_idx;
drop index if exists public.marketplace_card_urls_unique_language_slug_idx;
drop index if exists public.marketplace_card_urls_unique_language_slug_normalized_idx;

create index if not exists marketplace_card_urls_language_slug_idx
  on public.marketplace_card_urls (language, canonical_slug);

create index if not exists marketplace_card_urls_language_slug_normalized_idx
  on public.marketplace_card_urls (language, canonical_slug_normalized);

create index if not exists marketplace_card_urls_canonical_path_idx
  on public.marketplace_card_urls (canonical_path);

create index if not exists marketplace_card_urls_canonical_path_normalized_idx
  on public.marketplace_card_urls (canonical_path_normalized);

create index if not exists marketplace_card_urls_uniqueness_idx
  on public.marketplace_card_urls (is_unique, duplicate_group_size desc, language, canonical_slug_normalized);

create unique index if not exists marketplace_card_urls_unique_canonical_path_idx
  on public.marketplace_card_urls (canonical_path)
  where is_unique;

create unique index if not exists marketplace_card_urls_unique_canonical_path_normalized_idx
  on public.marketplace_card_urls (canonical_path_normalized)
  where is_unique;

create table if not exists public.marketplace_pokemon_name_roots (
  pokemon_name text primary key,
  normalized_name text not null,
  compact_name text not null,
  name_tokens text[] not null default '{}'::text[],
  source text not null default 'fixture',
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_pokemon_name_roots_normalized_idx
  on public.marketplace_pokemon_name_roots (normalized_name);

create index if not exists marketplace_pokemon_name_roots_compact_idx
  on public.marketplace_pokemon_name_roots (compact_name);

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

create table if not exists public.marketplace_name_ngrams (
  card_id bigint not null,
  name text not null,
  language text not null default 'en',
  source text not null default 'canonical_name',
  chunk text not null,
  chunk_length smallint not null check (chunk_length between 2 and 4),
  chunk_position smallint not null,
  is_prefix boolean not null default false,
  source_weight real not null default 1,
  updated_at timestamptz not null default now(),
  primary key (card_id, language, source, chunk, chunk_position)
);

create index if not exists marketplace_name_ngrams_chunk_idx
  on public.marketplace_name_ngrams (language, chunk, is_prefix, source_weight desc, card_id);

create index if not exists marketplace_name_ngrams_card_idx
  on public.marketplace_name_ngrams (card_id, language);

alter table public.marketplace_name_ngrams
  drop constraint if exists marketplace_name_ngrams_card_id_fkey;

create table if not exists public.marketplace_query_chunk_events (
  language text not null default 'en',
  chunk text not null,
  next_chunk text not null default '',
  event_type text not null default 'search',
  event_count bigint not null default 0,
  total_weight bigint not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (language, chunk, next_chunk, event_type)
);

create index if not exists marketplace_query_chunk_events_hot_idx
  on public.marketplace_query_chunk_events (language, event_type, total_weight desc, last_seen_at desc);

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

create table if not exists public.marketplace_card_emoji_rules (
  name text primary key references public.marketplace_card_names(name) on delete cascade,
  emoji_a text not null,
  emoji_b text not null,
  source text not null default 'manual',
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_card_emoji_rules_lower_name_idx
  on public.marketplace_card_emoji_rules (lower(name));

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

create table if not exists public.marketplace_cm_expansion_rules (
  expansion_name text not null,
  cardmarket_locale text not null default 'en',
  cardtrader_expansion_code text not null default '',
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
  source text not null default '',
  notes text not null default '',
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (expansion_name, cardmarket_locale, applies_to_card_type)
);

create index if not exists marketplace_cm_expansion_rules_lookup_idx
  on public.marketplace_cm_expansion_rules (expansion_name, cardmarket_locale, confidence);

create index if not exists marketplace_cm_expansion_rules_slug_idx
  on public.marketplace_cm_expansion_rules (cardmarket_expansion_slug, cardmarket_locale);

create table if not exists public.marketplace_cm_verified_links (
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  cardmarket_locale text not null default 'en',
  cardmarket_url text not null,
  cardmarket_product_slug text not null default '',
  card_name text not null default '',
  expansion_name text not null default '',
  collector_number text not null default '',
  source text not null default '',
  confidence text not null default 'verified' check (
    confidence in ('verified', 'manual')
  ),
  notes text not null default '',
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (blueprint_id, cardmarket_locale)
);

create unique index if not exists marketplace_cm_verified_links_url_idx
  on public.marketplace_cm_verified_links (cardmarket_url);

create index if not exists marketplace_cm_verified_links_expansion_idx
  on public.marketplace_cm_verified_links (expansion_name, cardmarket_locale, verified_at desc);

create table if not exists public.marketplace_cm_scrape_observations (
  id uuid primary key default gen_random_uuid(),
  cardmarket_url text not null,
  cardmarket_locale text not null default 'en',
  cardmarket_expansion_slug text not null default '',
  cardmarket_product_slug text not null default '',
  page_title text not null default '',
  scraped_name text not null default '',
  scraped_expansion text not null default '',
  collector_number text not null default '',
  collector_prefix text not null default '',
  numeric_collector_number text not null default '',
  raw_title text not null default '',
  structured_payload jsonb not null default '{}'::jsonb,
  page_context jsonb not null default '{}'::jsonb,
  matched_blueprint_id bigint references public.cardtrader_pokemon_blueprints(id) on delete set null,
  match_confidence numeric,
  match_payload jsonb not null default '{}'::jsonb,
  source text not null default 'pokemon-card-extension',
  extension_version text not null default '',
  user_agent text not null default '',
  debug_uid text not null default '',
  debug_email text not null default '',
  status text not null default 'observed' check (
    status in ('observed', 'matched', 'verified', 'rejected')
  ),
  notes text not null default '',
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_cm_scrape_observations_url_idx
  on public.marketplace_cm_scrape_observations (cardmarket_url);

create index if not exists marketplace_cm_scrape_observations_status_idx
  on public.marketplace_cm_scrape_observations (status, observed_at desc);

create index if not exists marketplace_cm_scrape_observations_blueprint_idx
  on public.marketplace_cm_scrape_observations (matched_blueprint_id, observed_at desc);

create table if not exists public.marketplace_cm_refinement_log (
  id bigserial primary key,
  blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
  cardmarket_locale text not null default 'en',
  pasted_cardmarket_url text not null,
  candidate_cardmarket_url text not null default '',
  card_name text not null default '',
  expansion_name text not null default '',
  collector_number text not null default '',
  cardmarket_ids text[] not null default '{}',
  status text not null default 'pending' check (
    status in ('pending', 'implemented', 'rejected')
  ),
  debug_uid text not null default '',
  debug_email text not null default '',
  debug_username text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  implemented_at timestamptz
);

create index if not exists marketplace_cm_refinement_log_blueprint_idx
  on public.marketplace_cm_refinement_log (blueprint_id, status, created_at desc);

create index if not exists marketplace_cm_refinement_log_status_idx
  on public.marketplace_cm_refinement_log (status, created_at desc);

