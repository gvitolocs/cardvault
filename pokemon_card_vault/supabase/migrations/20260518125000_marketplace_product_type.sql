alter table public.marketplace_cards
  add column if not exists product_type text not null default 'card';

alter table public.marketplace_card_versions
  add column if not exists product_type text not null default 'card';

create index if not exists marketplace_cards_product_type_idx
  on public.marketplace_cards (product_type, imported_at desc nulls last);

create index if not exists marketplace_card_versions_product_type_idx
  on public.marketplace_card_versions (
    product_type,
    expansion_name,
    expansion_number_int,
    expansion_number
  );

create or replace function public.classify_marketplace_product_type(
  item_name text,
  expansion_name text default '',
  category_name text default '',
  item_type text default '',
  raw_number text default '',
  version_name text default '',
  blueprint_id bigint default null
)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      lower(coalesce(item_name, '')) as name,
      lower(coalesce(expansion_name, '')) as expansion,
      lower(coalesce(category_name, '')) as category,
      lower(coalesce(item_type, '')) as type,
      lower(coalesce(raw_number, '')) as number,
      lower(coalesce(version_name, '')) as version,
      coalesce(blueprint_id::text, '') as id_text
  ),
  signals as (
    select
      *,
      nullif(trim(version), '') is not null as has_version,
      number ~ '^[0-9]{1,4}[a-z]?/[0-9]{1,4}' as has_collector_number,
      number = id_text or number ~ '^[0-9]{5,}$' as looks_like_blueprint_number,
      expansion ~ 'world championship decks|world championships .* deck' as is_championship_set
    from normalized
  )
  select case
    when has_collector_number
    then 'card'
    when name ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
    then 'booster_box'
    when name ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
    then 'booster_bundle'
    when name ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
    then 'booster_pack'
    when name ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
    then 'elite_trainer_box'
    when name ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
    then 'tin'
    when name ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|collection)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|collection)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|collection)([^a-z0-9]|$)'
    then 'collection_box'
    when name ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
    then 'deck'
    when is_championship_set and not has_collector_number and (not has_version or looks_like_blueprint_number)
    then 'championship_deck'
    when name ~ '(^|[^a-z0-9])(coin|sleeves|playmat|binder|portfolio|accessory)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(coin|sleeves|playmat|binder|portfolio|accessory)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(coin|sleeves|playmat|binder|portfolio|accessory)([^a-z0-9]|$)'
    then 'accessory'
    when (category ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or name ~ '(^|[^a-z0-9])(sealed product|sealed case|product)([^a-z0-9]|$)')
      and not has_collector_number
    then 'sealed_product'
    else 'card'
  end
  from signals;
$$;

create or replace function public.classify_marketplace_item_kind(
  item_name text,
  category_name text default '',
  item_type text default '',
  expansion_name text default '',
  raw_number text default '',
  version_name text default '',
  blueprint_id bigint default null
)
returns text
language sql
immutable
as $$
  select case
    when public.classify_marketplace_product_type(
      item_name,
      expansion_name,
      category_name,
      item_type,
      raw_number,
      version_name,
      blueprint_id
    ) = 'card'
    then 'single'
    else 'product'
  end;
$$;

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
    product_type
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
    source.product_type
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
      ) as product_type
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
    product_type = excluded.product_type;

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
    product_type
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
    source.product_type
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
      ) as product_type
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
    product_type = excluded.product_type;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

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
      'tags', jsonb_build_array(cards.set_name, cards.rarity, cards.card_type, cards.item_kind, cards.product_type),
      'condition', 'NM',
      'isGraded', false,
      'itemKind', cards.item_kind,
      'productType', cards.product_type,
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

select public.refresh_marketplace_cards_from_blueprints();
select public.refresh_marketplace_card_versions();
