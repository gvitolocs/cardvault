-- Lightweight Supabase name-index tier for marketplace searchbar/autocomplete.
-- This is a derived cache from Oracle Postgres, not a marketplace replica.
-- Do not add listings, prices, users, full blueprint JSON, or write paths here.

create extension if not exists pg_trgm;

create table if not exists public.marketplace_card_name_index (
  card_id bigint not null,
  language text not null default 'en',
  display_name text not null,
  canonical_name text not null,
  search_name text not null,
  normalized_name text not null,
  compact_name text not null,
  name_tokens text[] not null default '{}',
  set_name text not null default '',
  card_number text not null default '',
  product_variant text not null default '',
  rarity text not null default '',
  card_type text not null default '',
  item_kind text not null default 'single',
  product_type text not null default '',
  trainer_name text not null default '',
  emoji text not null default '',
  search_weight real not null default 0,
  oracle_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (card_id, language, search_name)
);

alter table public.marketplace_card_name_index enable row level security;

create index if not exists marketplace_card_name_index_prefix_idx
  on public.marketplace_card_name_index (
    language,
    compact_name text_pattern_ops,
    search_weight desc,
    card_id
  );

create index if not exists marketplace_card_name_index_tokens_idx
  on public.marketplace_card_name_index using gin (name_tokens);

create index if not exists marketplace_card_name_index_normalized_trgm_idx
  on public.marketplace_card_name_index using gin (normalized_name gin_trgm_ops);

create index if not exists marketplace_card_name_index_card_idx
  on public.marketplace_card_name_index (card_id, language);
