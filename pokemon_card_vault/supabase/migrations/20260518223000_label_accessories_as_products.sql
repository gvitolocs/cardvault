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
    case
      when source.product_type = 'card' then source.source_rarity
      else initcap(replace(source.product_type, '_', ' '))
    end as rarity,
    case
      when source.product_type = 'card' then source.source_card_type
      when source.product_type = 'accessory' then 'Accessory'
      else initcap(replace(source.product_type, '_', ' '))
    end as card_type,
    source.card_number,
    source.product_type = 'card' and lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_holo,
    source.product_type = 'card' and lower(coalesce(b.blueprint->>'rarity', '')) like '%holo%' as is_foil,
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
      ) as source_rarity,
      coalesce(
        nullif(b.blueprint->>'card_type', ''),
        nullif(b.blueprint->>'type', ''),
        nullif(b.blueprint->>'category_name', ''),
        'Trading card'
      ) as source_card_type,
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

select public.refresh_marketplace_cards_from_blueprints();
select public.refresh_marketplace_card_versions();
select public.refresh_marketplace_search_candidates();
