create or replace function public.marketplace_expansion_number_int(value text)
returns integer
language sql
immutable
as $$
  select nullif(
    coalesce(
      substring(coalesce(value, '') from '([0-9]{1,4})/[0-9]{1,4}'),
      substring(coalesce(value, '') from '([0-9]+)')
    ),
    ''
  )::integer;
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
    public.marketplace_expansion_number_int(source.expansion_number),
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

select public.refresh_marketplace_card_versions();
