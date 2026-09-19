-- Browse rails on the Pi primary. Replaces Supabase marketplace_rails / marketplace_card_tiles.
-- Public JSON uses card_id only. leftover ct_id is never stored in cards jsonb.

create table if not exists public.marketplace_rails (
  id text primary key,
  cards jsonb not null default '[]'::jsonb,
  meta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_card_tiles (
  card_id text primary key,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_card_url_hash4 (
  card_id bigint primary key
    references public.marketplace_search_candidates(card_id) on delete cascade,
  hash4 smallint not null check (hash4 between 0 and 15),
  url_stem text not null,
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_card_url_hash4_lookup_idx
  on public.marketplace_card_url_hash4 (card_id, hash4);
