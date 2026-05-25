create table if not exists public.flutter_debug_logs (
  id bigserial primary key,
  received_at timestamptz not null default now(),
  client_timestamp timestamptz,
  session_id text not null,
  debug_user_uid text not null default '',
  client_user_id text not null default '',
  route_path text not null default '',
  browser_url text not null default '',
  event_name text not null,
  category text not null default 'flutter',
  payload jsonb not null default '{}'::jsonb
);

create index if not exists flutter_debug_logs_recent_idx
  on public.flutter_debug_logs (received_at desc, id desc);

create index if not exists flutter_debug_logs_session_recent_idx
  on public.flutter_debug_logs (session_id, received_at desc);

create index if not exists flutter_debug_logs_user_recent_idx
  on public.flutter_debug_logs (debug_user_uid, received_at desc);

create index if not exists flutter_debug_logs_path_recent_idx
  on public.flutter_debug_logs (route_path, received_at desc);

create index if not exists flutter_debug_logs_category_recent_idx
  on public.flutter_debug_logs (category, received_at desc);
