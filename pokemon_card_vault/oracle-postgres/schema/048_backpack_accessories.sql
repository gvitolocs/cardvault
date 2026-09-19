-- CardTrader files League Promo / Pokemon Center backpacks as Pokemon singles
-- with a region (Europe) as collector number. Those are bags, not cards.
-- Trainer cards such as Nemona's Backpack 083/091 stay singles via n/m.

set statement_timeout = 0;

create or replace function public.classify_marketplace_product_type(
  card_name text,
  expansion_name text default '',
  category_name text default '',
  blueprint_type text default '',
  card_number text default '',
  version text default '',
  blueprint_id bigint default null
)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      lower(coalesce(card_name, '')) as name,
      lower(coalesce(expansion_name, '')) as expansion,
      lower(coalesce(category_name, '')) as category,
      lower(coalesce(blueprint_type, '')) as type,
      lower(coalesce(card_number, '')) as number,
      lower(coalesce(version, '')) as version_text,
      coalesce(blueprint_id::text, '') as id_text
  ),
  signals as (
    select
      *,
      nullif(trim(version_text), '') is not null as has_version,
      number ~ '[0-9]{1,4}[a-z]?/[0-9]{1,4}' as has_collector_number,
      number = id_text or number ~ '^[0-9]{5,}$' as looks_like_blueprint_number,
      expansion ~ 'world championship decks|world championships .* deck' as is_championship_set
    from normalized
  )
  select case
    when has_collector_number
    then 'card'
    when name ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory|bag|shoulder bag|backpack)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory|bag|shoulder bag|backpack)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory|bag|shoulder bag|backpack)([^a-z0-9]|$)'
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
    when name ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
    then 'collection_box'
    when name ~ '(^|[^a-z0-9])(theme decks?|starter decks?|battle decks?|decks?)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(theme decks?|starter decks?|battle decks?|decks?)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(theme decks?|starter decks?|battle decks?|decks?)([^a-z0-9]|$)'
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

update public.marketplace_search_candidates
set
  product_type = 'accessory',
  item_kind = 'product'
where item_kind = 'single'
  and product_type = 'card'
  and name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(card_number, '') !~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}';

update public.marketplace_cards
set
  product_type = 'accessory',
  item_kind = 'product'
where item_kind = 'single'
  and product_type = 'card'
  and name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(card_number, '') !~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}';

update public.marketplace_card_versions
set product_type = 'accessory'
where product_type = 'card'
  and name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(expansion_number, '') !~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}';

-- Restore trainer cards whose n/m sits after a variant prefix (CSV6C | 117/128).
update public.marketplace_search_candidates
set
  product_type = 'card',
  item_kind = 'single'
where name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(card_number, '') ~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}'
  and (item_kind <> 'single' or product_type <> 'card');

update public.marketplace_cards
set
  product_type = 'card',
  item_kind = 'single'
where name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(card_number, '') ~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}'
  and (item_kind <> 'single' or product_type <> 'card');

update public.marketplace_card_versions
set product_type = 'card'
where name ~* '(^|[^a-z0-9])backpack([^a-z0-9]|$)'
  and coalesce(expansion_number, '') ~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}'
  and product_type <> 'card';
