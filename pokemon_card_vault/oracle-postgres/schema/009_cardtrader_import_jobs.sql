create table if not exists public.marketplace_cardtrader_import_jobs (
  job_id text primary key,
  game text not null,
  mode text not null check (mode in ('dry_run', 'apply')),
  status text not null default 'queued' check (
    status in ('queued', 'running', 'succeeded', 'failed', 'cancelled')
  ),
  requested_by_uid text not null default '',
  requested_by_email text not null default '',
  requested_by_username text not null default '',
  request_payload jsonb not null default '{}'::jsonb,
  worker_id text not null default '',
  attempt_count integer not null default 0,
  progress jsonb not null default '{}'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  error_message text not null default '',
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  heartbeat_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_cardtrader_import_jobs_one_active_game_idx
  on public.marketplace_cardtrader_import_jobs (lower(game))
  where status in ('queued', 'running');

create index if not exists marketplace_cardtrader_import_jobs_status_idx
  on public.marketplace_cardtrader_import_jobs (status, requested_at desc);

create index if not exists marketplace_cardtrader_import_jobs_game_recent_idx
  on public.marketplace_cardtrader_import_jobs (lower(game), requested_at desc);
