-- Minimal Firebase Auth user dimension for Oracle analytics/personalization.
-- Stores stable account metadata only; never store Firebase ID tokens,
-- refresh tokens, password hashes, or custom claims here.

create table if not exists public.marketplace_firebase_users (
  user_uid text primary key,
  email text,
  display_name text,
  photo_url text,
  disabled boolean not null default false,
  email_verified boolean not null default false,
  provider_ids text[] not null default '{}'::text[],
  firebase_created_at timestamptz,
  firebase_last_sign_in_at timestamptz,
  synced_at timestamptz not null default now()
);

create index if not exists marketplace_firebase_users_synced_at_idx
  on public.marketplace_firebase_users (synced_at desc);

create index if not exists marketplace_firebase_users_last_sign_in_idx
  on public.marketplace_firebase_users (firebase_last_sign_in_at desc nulls last);

