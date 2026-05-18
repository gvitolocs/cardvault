create table if not exists public.marketplace_cards (
  card_id bigint primary key,
  name text not null,
  version text,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  set_name text not null default 'Pokemon',
  rarity text not null default 'Card',
  card_type text not null default 'Trading card',
  card_number text,
  is_holo boolean not null default false,
  is_foil boolean not null default false,
  imported_at timestamptz,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_cards_imported_at_idx
  on public.marketplace_cards (imported_at desc nulls last);

create index if not exists marketplace_cards_name_idx
  on public.marketplace_cards using gin (to_tsvector('simple', coalesce(name, '')));

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

create or replace function public.refresh_marketplace_cards_from_blueprints()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_cards (
    card_id,
    name,
    version,
    image_url,
    cdn_image_url,
    preview_image_url,
    set_name,
    rarity,
    card_type,
    card_number,
    is_holo,
    is_foil,
    imported_at,
    projected_at
  )
  select
    b.id,
    b.name,
    b.version,
    b.image_url,
    b.cdn_image_url,
    b.preview_image_url,
    coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as set_name,
    coalesce(
      nullif(b.blueprint->>'rarity', ''),
      nullif(b.blueprint->>'collector_rarity', ''),
      'Card'
    ) as rarity,
    coalesce(
      nullif(b.blueprint->>'card_type', ''),
      nullif(b.blueprint->>'type', ''),
      nullif(b.blueprint->>'category_name', ''),
      'Trading card'
    ) as card_type,
    coalesce(
      nullif(b.blueprint->>'number', ''),
      nullif(b.blueprint->>'collector_number', ''),
      nullif(b.blueprint->>'card_number', ''),
      b.version,
      b.id::text
    ) as card_number,
    lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_holo,
    lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_foil,
    b.imported_at,
    now()
  from public.cardtrader_pokemon_blueprints b
  where b.cdn_image_url is not null
  on conflict (card_id) do update set
    name = excluded.name,
    version = excluded.version,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    set_name = excluded.set_name,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    card_number = excluded.card_number,
    is_holo = excluded.is_holo,
    is_foil = excluded.is_foil,
    imported_at = excluded.imported_at,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.get_marketplace_home_snapshot(result_limit integer default 120)
returns jsonb
language sql
stable
set search_path = public
as $$
  with recent_events as (
    select
      card_id,
      count(*) filter (where event_type = 'view') as views_24h,
      count(*) filter (where event_type = 'search') as searches_24h,
      count(*) filter (where event_type = 'click') as clicks_24h,
      count(*) filter (where event_type = 'reserve') as reserves_24h,
      count(*) filter (where event_type = 'cart_add') as cart_adds_24h,
      count(*) filter (where event_type = 'sale') as sales_24h,
      coalesce(sum(weight), 0) as weighted_events_24h
    from public.marketplace_card_events
    where occurred_at >= now() - interval '24 hours'
    group by card_id
  ),
  scored as (
    select
      c.*,
      coalesce(e.views_24h, 0) as views_24h,
      coalesce(e.searches_24h, 0) as searches_24h,
      coalesce(e.clicks_24h, 0) as clicks_24h,
      coalesce(e.reserves_24h, 0) as reserves_24h,
      coalesce(e.cart_adds_24h, 0) as cart_adds_24h,
      coalesce(e.sales_24h, 0) as sales_24h,
      (
        coalesce(e.views_24h, 0) * 1 +
        coalesce(e.searches_24h, 0) * 2 +
        coalesce(e.clicks_24h, 0) * 4 +
        coalesce(e.cart_adds_24h, 0) * 8 +
        coalesce(e.reserves_24h, 0) * 10 +
        coalesce(e.sales_24h, 0) * 20 +
        case when c.is_holo or c.rarity ilike '%rare%' then 5 else 0 end
      )::numeric as spotlight_score
    from public.marketplace_cards c
    left join recent_events e on e.card_id = c.card_id
  ),
  cards as (
    select *
    from scored
    order by spotlight_score desc, imported_at desc nulls last, card_id desc
    limit greatest(1, least(result_limit, 500))
  ),
  recent_ids as (
    select coalesce(jsonb_agg(card_id::text order by imported_at desc nulls last, card_id desc), '[]'::jsonb) ids
    from (select * from scored order by imported_at desc nulls last, card_id desc limit 12) r
  ),
  spotlight_ids as (
    select coalesce(jsonb_agg(card_id::text order by spotlight_score desc, imported_at desc nulls last), '[]'::jsonb) ids
    from (select * from scored order by spotlight_score desc, imported_at desc nulls last limit 12) s
  ),
  featured_ids as (
    select coalesce(jsonb_agg(card_id::text order by is_holo desc, rarity desc, imported_at desc nulls last), '[]'::jsonb) ids
    from (
      select *
      from scored
      where is_holo or rarity ilike '%rare%' or rarity ilike '%promo%'
      order by is_holo desc, rarity desc, imported_at desc nulls last
      limit 12
    ) f
  )
  select jsonb_build_object(
    'generatedAt', now(),
    'window', jsonb_build_object(
      'lookbackHours', 24,
      'persistentSpotlight', false
    ),
    'cards', coalesce(jsonb_agg(jsonb_build_object(
      'id', cards.card_id::text,
      'name', cards.name,
      'imageUrl', cards.cdn_image_url,
      'previewImageUrl', coalesce(cards.preview_image_url, cards.cdn_image_url, cards.image_url),
      'rarity', cards.rarity,
      'type', cards.card_type,
      'hp', 0,
      'attacks', '[]'::jsonb,
      'price', 1000 + (cards.card_id % 120000),
      'description', 'Imported from the Pokoin marketplace projection. Full blueprint data is loaded only on card detail.',
      'set', cards.set_name,
      'number', coalesce(cards.card_number, cards.version, cards.card_id::text),
      'artist', '',
      'stock', 0,
      'rating', 0,
      'reviewCount', 0,
      'isFoil', cards.is_foil,
      'isHolo', cards.is_holo,
      'releaseDate', now(),
      'tags', jsonb_build_array(cards.set_name, cards.rarity, cards.card_type),
      'condition', 'NM',
      'isGraded', false,
      'analytics', jsonb_build_object(
        'views24h', cards.views_24h,
        'searches24h', cards.searches_24h,
        'clicks24h', cards.clicks_24h,
        'reserves24h', cards.reserves_24h,
        'cartAdds24h', cards.cart_adds_24h,
        'sales24h', cards.sales_24h,
        'spotlightScore', cards.spotlight_score
      )
    ) order by cards.spotlight_score desc, cards.imported_at desc nulls last), '[]'::jsonb),
    'sections', jsonb_build_object(
      'recentlySeenIds', (select ids from recent_ids),
      'bestSellerIds', (select ids from spotlight_ids),
      'featuredIds', (select ids from featured_ids)
    )
  )
  from cards;
$$;

alter table public.marketplace_cards enable row level security;
alter table public.marketplace_card_events enable row level security;

drop policy if exists "Marketplace cards are publicly readable" on public.marketplace_cards;
create policy "Marketplace cards are publicly readable"
  on public.marketplace_cards
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Marketplace analytics events are insertable" on public.marketplace_card_events;
create policy "Marketplace analytics events are insertable"
  on public.marketplace_card_events
  for insert
  to anon, authenticated
  with check (
    occurred_at >= now() - interval '5 minutes'
    and occurred_at <= now() + interval '5 minutes'
  );

drop policy if exists "Marketplace analytics are not publicly readable" on public.marketplace_card_events;
create policy "Marketplace analytics are not publicly readable"
  on public.marketplace_card_events
  for select
  to authenticated
  using (false);

select public.refresh_marketplace_cards_from_blueprints();
