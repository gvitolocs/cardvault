-- Scan Connect: desktop ↔ phone pairing, persistent scan batches, staged
-- scan rows, and listing location. Apply on the Oracle/nezopt **primary**
-- (MARKETPLACE_WRITER_DATABASE_URL); the Pi replica follows.
--
-- Spec: pokoin-web docs/SCAN_CONNECT.md, docs/SCAN_LISTING_WORKFLOW.md.
--
-- Pairing (minutes, security) · session (working session, phone credential)
-- · batch (the seller's persistent work) · item (immutable scan event +
-- mutable staged article) are separate on purpose. A pairing row is deleted
-- when it is claimed; that delete is the single-use guarantee.

begin;

create extension if not exists pgcrypto;

create table if not exists public.scan_batches (
  id uuid primary key default gen_random_uuid(),
  seller_uid text not null,
  status text not null default 'open'
    check (status in ('open', 'submitted', 'discarded')),
  title text not null default '',
  defaults jsonb not null default '{}'::jsonb,
  defaults_version integer not null default 1 check (defaults_version >= 1),
  -- [{version, changedAt (epoch ms, server clock), defaults}] oldest first
  defaults_history jsonb not null default '[]'::jsonb,
  item_seq bigint not null default 0,
  item_position integer not null default 0,
  submit_key text,
  submit_result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz
);

create index if not exists scan_batches_seller_open_idx
  on public.scan_batches (seller_uid, status, updated_at desc);

create table if not exists public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  seller_uid text not null,
  batch_id uuid not null references public.scan_batches(id) on delete cascade,
  status text not null default 'waiting'
    check (status in ('waiting', 'connected', 'ended')),
  end_reason text
    check (end_reason is null or end_reason in ('completed', 'expired', 'logout', 'replaced', 'discarded')),
  paused boolean not null default false,
  phone_token_hash text unique,
  phone_label text not null default '',
  phone_connected_at timestamptz,
  phone_last_seen_at timestamptz,
  phone_scans integer not null default 0,
  last_scan_at timestamptz,
  last_activity_at timestamptz not null default now(),
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists scan_sessions_batch_idx
  on public.scan_sessions (batch_id, created_at desc);

create index if not exists scan_sessions_seller_live_idx
  on public.scan_sessions (seller_uid, status)
  where status <> 'ended';

create table if not exists public.scan_pairings (
  pin char(4) primary key check (pin ~ '^[0-9]{4}$'),
  session_id uuid not null unique references public.scan_sessions(id) on delete cascade,
  -- Plain, like the PIN beside it: lives <= 120 s and is deleted on claim.
  -- Hashing it would force a regenerate for every extra dashboard tab.
  qr_secret text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists scan_pairings_expires_idx
  on public.scan_pairings (expires_at);

-- Fixed-window counters for pairing / session limits. Postgres, not Valkey:
-- the Valkey client returns null on error and a security limit must fail
-- closed.
create table if not exists public.scan_rate_limits (
  bucket text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (bucket, window_start)
);

create index if not exists scan_rate_limits_window_idx
  on public.scan_rate_limits (window_start);

create table if not exists public.scan_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.scan_batches(id) on delete cascade,
  seller_uid text not null,

  -- Immutable scan event (null for manual rows). Guarded by trigger below.
  scan_event_id uuid unique,
  session_id uuid references public.scan_sessions(id) on delete set null,
  client_sequence integer,
  captured_at timestamptz,
  received_at timestamptz not null default now(),
  recognition_state text not null
    check (recognition_state in ('matched', 'ambiguous', 'unmatched', 'manual')),
  recognition jsonb not null default '{}'::jsonb,
  defaults_version integer,
  defaults_snapshot jsonb not null default '{}'::jsonb,
  image bytea check (image is null or octet_length(image) <= 60000),
  timings jsonb not null default '{}'::jsonb,

  -- Mutable staged article.
  seq bigint not null,
  position double precision not null,
  status text not null default 'active'
    check (status in ('active', 'removed', 'merged', 'submitted')),
  merged_into uuid references public.scan_items(id) on delete set null,
  reviewed boolean not null default false,
  card_id text,
  card_name text not null default '',
  set_name text not null default '',
  collector_number text not null default '',
  image_url text not null default '',
  nationality text not null default '',
  condition text not null default 'NM',
  language text not null default 'EN',
  foil_state text not null default 'standard',
  first_edition boolean not null default false,
  signed boolean not null default false,
  altered boolean not null default false,
  graded boolean not null default false,
  grading_company text,
  grade text,
  certification_id text,
  location text not null default '',
  quantity integer not null default 1 check (quantity >= 1 and quantity <= 99),
  price_pkn numeric check (price_pkn is null or price_pkn > 0),
  price_suggested boolean not null default false,
  seller_comment text not null default '',
  listing_id uuid,
  updated_at timestamptz not null default now()
);

create index if not exists scan_items_batch_seq_idx
  on public.scan_items (batch_id, seq);

create index if not exists scan_items_batch_position_idx
  on public.scan_items (batch_id, position);

create or replace function public.scan_items_guard_event()
returns trigger
language plpgsql
as $$
begin
  if new.scan_event_id is distinct from old.scan_event_id
    or new.session_id is distinct from old.session_id and new.session_id is not null
    or new.client_sequence is distinct from old.client_sequence
    or new.captured_at is distinct from old.captured_at
    or new.received_at is distinct from old.received_at
    or new.recognition_state is distinct from old.recognition_state
    or new.recognition is distinct from old.recognition
    or new.defaults_version is distinct from old.defaults_version
    or new.defaults_snapshot is distinct from old.defaults_snapshot
    or new.image is distinct from old.image
    or new.batch_id is distinct from old.batch_id
    or new.seller_uid is distinct from old.seller_uid then
    raise exception 'scan event columns are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists scan_items_guard_event on public.scan_items;
create trigger scan_items_guard_event
  before update on public.scan_items
  for each row execute function public.scan_items_guard_event();

-- Listings: physical location and altered flag. Location is private to the
-- seller (never in public listing reads).
alter table public.marketplace_user_listings
  add column if not exists location text not null default '';

alter table public.marketplace_user_listings
  add column if not exists altered boolean not null default false;

-- Submit idempotency: one listing per staged scan row, ever.
create unique index if not exists marketplace_user_listings_scan_row_uidx
  on public.marketplace_user_listings (source_listing_id)
  where source = 'pokoin_scan_batch';

commit;
