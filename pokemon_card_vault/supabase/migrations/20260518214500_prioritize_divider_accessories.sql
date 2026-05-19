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
    when name ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
    then 'accessory'
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
    when name ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection)([^a-z0-9]|$)'
    then 'collection_box'
    when name ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
    then 'deck'
    when is_championship_set and not has_collector_number and (not has_version or looks_like_blueprint_number)
    then 'championship_deck'
    when (category ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or name ~ '(^|[^a-z0-9])(sealed product|sealed case|product)([^a-z0-9]|$)')
      and not has_collector_number
    then 'sealed_product'
    else 'card'
  end
  from signals;
$$;

select public.refresh_marketplace_cards_from_blueprints();
select public.refresh_marketplace_card_versions();
select public.refresh_marketplace_search_candidates();
