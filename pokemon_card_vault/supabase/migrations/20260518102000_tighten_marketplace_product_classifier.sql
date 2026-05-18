create or replace function public.classify_marketplace_item_kind(
  item_name text,
  category_name text default '',
  item_type text default ''
)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(category_name, '')) ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or lower(coalesce(item_type, '')) ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or lower(coalesce(item_name, '')) ~ '(^|[^a-z0-9])(booster box|booster pack|booster bundle|elite trainer box|etb|gift box|collection box|premium collection|trainer toolkit|battle deck|theme deck|starter deck|blister pack|build & battle|build and battle|display box|sealed case|collector chest|tin)([^a-z0-9]|$)'
    then 'product'
    else 'single'
  end;
$$;

update public.marketplace_cards c
set item_kind = public.classify_marketplace_item_kind(
  b.name,
  b.blueprint->>'category_name',
  b.blueprint->>'type'
)
from public.cardtrader_pokemon_blueprints b
where b.id = c.card_id;
