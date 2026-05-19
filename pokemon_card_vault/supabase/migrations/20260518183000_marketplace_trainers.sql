create table if not exists public.marketplace_trainers (
  trainer_name text primary key,
  aliases text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.marketplace_cards
  add column if not exists trainer_name text not null default '';

alter table public.marketplace_card_versions
  add column if not exists trainer_name text not null default '';

create index if not exists marketplace_cards_trainer_name_idx
  on public.marketplace_cards (trainer_name)
  where trainer_name <> '';

create index if not exists marketplace_card_versions_trainer_name_idx
  on public.marketplace_card_versions (trainer_name, expansion_name)
  where trainer_name <> '';

create or replace function public.extract_marketplace_trainer_name(item_name text)
returns text
language sql
immutable
as $$
  with normalized as (
    select trim(coalesce(item_name, '')) as name
  ),
  extracted as (
    select case
      when name ~* '^(Cynthia|Lance|Misty|Brock|Clair|Steven|Lillie|Gladion|Marnie|Leon|Raihan|Iono|N|Erika|Giovanni|Sabrina|Iris|Diantha|Hop|Nemona|Peonia)''s[[:space:]]+.+$'
      then nullif(trim((regexp_match(name, '^(Cynthia|Lance|Misty|Brock|Clair|Steven|Lillie|Gladion|Marnie|Leon|Raihan|Iono|N|Erika|Giovanni|Sabrina|Iris|Diantha|Hop|Nemona|Peonia)''s[[:space:]]+.+$', 'i'))[1]), '')
      when name ~* '(^|[[:space:]])C([[:space:]]+LV\.[0-9X]+|$)'
      then 'Cynthia'
      else ''
    end as trainer
    from normalized
  )
  select coalesce(trainer, '')
  from extracted;
$$;

insert into public.marketplace_trainers (trainer_name, aliases)
select trainer_name, '{}'::text[]
from (
  select distinct public.extract_marketplace_trainer_name(name) as trainer_name
  from public.cardtrader_pokemon_blueprints
) trainers
where trainer_name <> ''
on conflict (trainer_name) do nothing;

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
    projected_at,
    item_kind,
    product_type,
    trainer_name
  )
  select
    b.id,
    b.name,
    b.version,
    b.image_url,
    b.cdn_image_url,
    b.preview_image_url,
    source.set_name,
    source.rarity,
    source.card_type,
    source.card_number,
    lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_holo,
    lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_foil,
    b.imported_at,
    now(),
    case when source.product_type = 'card' then 'single' else 'product' end,
    source.product_type,
    source.trainer_name
  from public.cardtrader_pokemon_blueprints b
  cross join lateral (
    select
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
      ) as card_number
  ) fields
  cross join lateral (
    select
      fields.*,
      public.classify_marketplace_product_type(
        b.name,
        fields.set_name,
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        fields.card_number,
        b.version,
        b.id
      ) as product_type,
      public.extract_marketplace_trainer_name(b.name) as trainer_name
  ) source
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
    projected_at = now(),
    item_kind = excluded.item_kind,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_card_versions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_card_versions (
    card_id,
    name,
    expansion_name,
    expansion_number,
    expansion_number_int,
    blueprint_id,
    image_url,
    cdn_image_url,
    preview_image_url,
    projected_at,
    product_type,
    trainer_name
  )
  select
    b.id,
    b.name,
    source.expansion_name,
    source.expansion_number,
    nullif(substring(source.expansion_number from '[0-9]+'), '')::integer,
    b.id as blueprint_id,
    b.image_url,
    b.cdn_image_url,
    b.preview_image_url,
    now(),
    source.product_type,
    source.trainer_name
  from public.cardtrader_pokemon_blueprints b
  cross join lateral (
    select
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as expansion_name,
      coalesce(
        nullif(b.blueprint->>'number', ''),
        nullif(b.blueprint->>'collector_number', ''),
        nullif(b.blueprint->>'card_number', ''),
        b.version,
        b.id::text
      ) as expansion_number
  ) fields
  cross join lateral (
    select
      fields.*,
      public.classify_marketplace_product_type(
        b.name,
        fields.expansion_name,
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        fields.expansion_number,
        b.version,
        b.id
      ) as product_type,
      public.extract_marketplace_trainer_name(b.name) as trainer_name
  ) source
  where b.cdn_image_url is not null
  on conflict (card_id) do update set
    name = excluded.name,
    expansion_name = excluded.expansion_name,
    expansion_number = excluded.expansion_number,
    expansion_number_int = excluded.expansion_number_int,
    blueprint_id = excluded.blueprint_id,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    projected_at = now(),
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

select public.refresh_marketplace_cards_from_blueprints();
select public.refresh_marketplace_card_versions();

create or replace function public.get_marketplace_home_snapshot(result_limit integer default 120)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with recent_events as (
    select
      card_id,
      sum(weight) filter (where event_type in ('view', 'click')) as demand_24h,
      sum(weight) filter (where event_type = 'sale') as sales_24h,
      count(*) filter (where event_type = 'cart_add') as cart_adds_24h
    from public.marketplace_card_events
    where occurred_at >= now() - interval '24 hours'
    group by card_id
  ),
  scored as (
    select
      c.*,
      (
        coalesce(e.demand_24h, 0) * 3 +
        coalesce(e.cart_adds_24h, 0) * 8 +
        coalesce(e.sales_24h, 0) * 20 +
        case when c.is_holo or c.rarity ilike '%rare%' then 5 else 0 end
      )::numeric as spotlight_score
    from public.marketplace_cards c
    left join recent_events e on e.card_id = c.card_id
  ),
  cards as (
    select *
    from scored
    order by spotlight_score desc, imported_at desc nulls last
    limit greatest(1, least(result_limit, 500))
  ),
  section_ids as (
    select
      coalesce(
        jsonb_agg(card_id::text order by imported_at desc nulls last)
          filter (where rn_recent <= 12),
        '[]'::jsonb
      ) as recently_seen_ids,
      coalesce(
        jsonb_agg(card_id::text order by spotlight_score desc, imported_at desc nulls last)
          filter (where rn_best <= 12),
        '[]'::jsonb
      ) as best_seller_ids,
      coalesce(
        jsonb_agg(card_id::text order by is_holo desc, spotlight_score desc, imported_at desc nulls last)
          filter (where rn_featured <= 12),
        '[]'::jsonb
      ) as featured_ids
    from (
      select
        cards.*,
        row_number() over (order by imported_at desc nulls last) as rn_recent,
        row_number() over (order by spotlight_score desc, imported_at desc nulls last) as rn_best,
        row_number() over (order by is_holo desc, spotlight_score desc, imported_at desc nulls last) as rn_featured
      from cards
    ) ranked
  )
  select jsonb_build_object(
    'generatedAt', now(),
    'cards', coalesce(jsonb_agg(jsonb_build_object(
      'id', cards.card_id::text,
      'name', cards.name,
      'imageUrl', coalesce(cards.cdn_image_url, cards.image_url, ''),
      'previewImageUrl', coalesce(cards.preview_image_url, cards.cdn_image_url, cards.image_url, ''),
      'rarity', cards.rarity,
      'type', cards.card_type,
      'hp', 0,
      'attacks', '[]'::jsonb,
      'price', (1000 + (cards.card_id % 120000))::numeric,
      'description', 'Imported from the Pokoin marketplace projection.',
      'set', cards.set_name,
      'number', coalesce(cards.card_number, cards.version, cards.card_id::text),
      'artist', '',
      'stock', 0,
      'rating', 0,
      'reviewCount', 0,
      'isFoil', cards.is_foil,
      'isHolo', cards.is_holo,
      'releaseDate', now(),
      'tags', jsonb_build_array(cards.set_name, cards.rarity, cards.card_type, cards.item_kind, cards.product_type, cards.trainer_name),
      'condition', 'NM',
      'isGraded', false,
      'itemKind', cards.item_kind,
      'productType', cards.product_type,
      'trainerName', cards.trainer_name,
      'analytics', jsonb_build_object(
        'spotlightScore', cards.spotlight_score
      )
    ) order by cards.spotlight_score desc, cards.imported_at desc nulls last), '[]'::jsonb),
    'sections', jsonb_build_object(
      'recentlySeenIds', (select recently_seen_ids from section_ids),
      'bestSellerIds', (select best_seller_ids from section_ids),
      'featuredIds', (select featured_ids from section_ids)
    )
  )
  from cards;
$$;
