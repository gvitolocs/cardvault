create table if not exists public.assistant_user_current_pages (
  session_id text not null,
  user_uid text not null default '',
  path text not null,
  source text not null default 'assistant',
  updated_at timestamptz not null default now(),
  primary key (session_id, user_uid),
  constraint assistant_user_current_pages_session_nonempty check (session_id <> ''),
  constraint assistant_user_current_pages_path_internal check (
    path like '/%' and path not like '//%' and position(E'\n' in path) = 0 and position(E'\r' in path) = 0
  )
);

create index if not exists assistant_user_current_pages_user_recent_idx
  on public.assistant_user_current_pages (user_uid, updated_at desc)
  where user_uid <> '';

create index if not exists assistant_user_current_pages_session_recent_idx
  on public.assistant_user_current_pages (session_id, updated_at desc);
