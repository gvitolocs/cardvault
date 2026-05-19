create extension if not exists pgcrypto;

create table if not exists public.forum_categories (
  id text primary key,
  title text not null,
  description text not null default '',
  icon_name text not null default 'forum',
  sort_order integer not null default 999,
  topic_count integer not null default 0 check (topic_count >= 0),
  post_count integer not null default 0 check (post_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.forum_topics (
  id uuid primary key default gen_random_uuid(),
  category_id text not null references public.forum_categories(id),
  title text not null check (char_length(title) between 6 and 120),
  body text not null check (char_length(body) between 12 and 5000),
  author_uid text not null,
  author_name text not null,
  author_photo_url text,
  reply_count integer not null default 0 check (reply_count >= 0),
  status text not null default 'open' check (status in ('open', 'locked', 'hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.forum_posts (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.forum_topics(id) on delete cascade,
  category_id text not null references public.forum_categories(id),
  body text not null check (char_length(body) between 3 and 5000),
  author_uid text not null,
  author_name text not null,
  author_photo_url text,
  status text not null default 'open' check (status in ('open', 'hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.forum_media (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null,
  topic_id uuid references public.forum_topics(id) on delete cascade,
  post_id uuid references public.forum_posts(id) on delete cascade,
  object_key text not null unique,
  public_url text not null,
  mime_type text not null,
  byte_size integer not null check (byte_size > 0),
  width integer,
  height integer,
  created_at timestamptz not null default now(),
  constraint forum_media_has_parent check (topic_id is not null or post_id is not null)
);

create table if not exists public.forum_topic_cards (
  topic_id uuid not null references public.forum_topics(id) on delete cascade,
  card_id bigint not null references public.marketplace_cards(card_id),
  created_at timestamptz not null default now(),
  primary key (topic_id, card_id)
);

create index if not exists forum_categories_sort_order_idx
  on public.forum_categories (sort_order, id);

create index if not exists forum_topics_latest_idx
  on public.forum_topics (status, updated_at desc, id desc);

create index if not exists forum_topics_category_latest_idx
  on public.forum_topics (category_id, status, updated_at desc, id desc);

create index if not exists forum_posts_topic_created_idx
  on public.forum_posts (topic_id, status, created_at asc, id asc);

create index if not exists forum_media_topic_idx
  on public.forum_media (topic_id, created_at asc);

create index if not exists forum_media_post_idx
  on public.forum_media (post_id, created_at asc);

create or replace function public.touch_forum_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists forum_categories_touch_updated_at on public.forum_categories;
create trigger forum_categories_touch_updated_at
before update on public.forum_categories
for each row execute function public.touch_forum_updated_at();

drop trigger if exists forum_topics_touch_updated_at on public.forum_topics;
create trigger forum_topics_touch_updated_at
before update on public.forum_topics
for each row execute function public.touch_forum_updated_at();

drop trigger if exists forum_posts_touch_updated_at on public.forum_posts;
create trigger forum_posts_touch_updated_at
before update on public.forum_posts
for each row execute function public.touch_forum_updated_at();

create or replace function public.bump_forum_topic_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.forum_categories
  set
    topic_count = topic_count + 1,
    post_count = post_count + 1
  where id = new.category_id;
  return new;
end;
$$;

drop trigger if exists forum_topics_bump_counts on public.forum_topics;
create trigger forum_topics_bump_counts
after insert on public.forum_topics
for each row execute function public.bump_forum_topic_counts();

create or replace function public.bump_forum_reply_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.forum_topics
  set
    reply_count = reply_count + 1,
    updated_at = now()
  where id = new.topic_id;

  update public.forum_categories
  set post_count = post_count + 1
  where id = new.category_id;

  return new;
end;
$$;

drop trigger if exists forum_posts_bump_counts on public.forum_posts;
create trigger forum_posts_bump_counts
after insert on public.forum_posts
for each row execute function public.bump_forum_reply_counts();

insert into public.forum_categories (
  id,
  title,
  description,
  icon_name,
  sort_order
)
values
  ('general', 'General', 'Community updates and open discussion.', 'forum', 10),
  ('cards', 'Cards', 'Collecting, grading, trades and marketplace ideas.', 'cards', 20),
  ('pkn', 'PKN and wPKN', 'Native PKN, wPKN liquidity and DeFi.', 'token', 30),
  ('validators', 'Validators', 'Nodes, RPC, staking and network operations.', 'validators', 40)
on conflict (id) do update set
  title = excluded.title,
  description = excluded.description,
  icon_name = excluded.icon_name,
  sort_order = excluded.sort_order;

alter table public.forum_categories enable row level security;
alter table public.forum_topics enable row level security;
alter table public.forum_posts enable row level security;
alter table public.forum_media enable row level security;
alter table public.forum_topic_cards enable row level security;

drop policy if exists forum_categories_public_read on public.forum_categories;
create policy forum_categories_public_read
on public.forum_categories
for select
using (true);

drop policy if exists forum_topics_public_read on public.forum_topics;
create policy forum_topics_public_read
on public.forum_topics
for select
using (status = 'open');

drop policy if exists forum_posts_public_read on public.forum_posts;
create policy forum_posts_public_read
on public.forum_posts
for select
using (status = 'open');

drop policy if exists forum_media_public_read on public.forum_media;
create policy forum_media_public_read
on public.forum_media
for select
using (true);

drop policy if exists forum_topic_cards_public_read on public.forum_topic_cards;
create policy forum_topic_cards_public_read
on public.forum_topic_cards
for select
using (true);
