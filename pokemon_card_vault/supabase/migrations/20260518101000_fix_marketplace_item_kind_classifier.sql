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
    when lower(coalesce(item_name, '')) ~ '(^|[^a-z0-9])(booster|box|pack|bundle|tin|deck|etb|elite trainer|collection|display|case|blister|starter|theme deck)([^a-z0-9]|$)'
      or lower(coalesce(category_name, '')) ~ '(^|[^a-z0-9])(sealed|booster|box|pack|deck|product)([^a-z0-9]|$)'
      or lower(coalesce(item_type, '')) ~ '(^|[^a-z0-9])(sealed|booster|box|pack|deck|product)([^a-z0-9]|$)'
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
