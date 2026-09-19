-- pokoin_public_number(ct_id) = ct_id * 2 = our marketplace/URL id.
-- After 018 on pokoin-marketplace, marketplace_cards.card_id IS that number; ct_id is the
-- scrape/CDN key. Do not generate public_number as card_id * 2 on that DB (4×).
-- Canonical: docs/marketplace-public-ids.md
create extension if not exists unaccent with schema public;

create or replace function public.pokoin_public_number(cardtrader_id bigint)
returns bigint
language sql
immutable
as $$
  select cardtrader_id * 2;
$$;

comment on function public.pokoin_public_number(bigint) is
  'Our marketplace/URL id = CardTrader blueprint/ct_id * 2. After 018, marketplace_cards.card_id already holds this; pass only raw ct_id.';

create or replace function public.marketplace_url_slug_part(value text)
returns text
language sql
stable
as $$
  select trim(both '-' from regexp_replace(
    lower(public.unaccent(coalesce(value, ''))),
    '[^a-z0-9]+',
    '-',
    'g'
  ));
$$;

create or replace function public.marketplace_card_url_collector_number(
  card_number text,
  card_id bigint
)
returns text
language sql
immutable
as $$
  select case
    when cleaned = '' or cleaned = card_id::text then ''
    else cleaned
  end
  from (
    select regexp_replace(trim(both from coalesce(card_number, '')), '^#+\s*', '') as cleaned
  ) source;
$$;

alter table public.marketplace_card_urls
  add column if not exists public_number bigint generated always as (card_id * 2) stored;

comment on column public.marketplace_card_urls.card_id is
  'CardTrader original / internal / CDN id. Not the public URL number.';

comment on column public.marketplace_card_urls.public_number is
  'Pokoin public/URL id = card_id * 2. Path numbers in /{n} and /marketplace/en/cards/{n}/...';

create unique index if not exists marketplace_card_urls_public_number_idx
  on public.marketplace_card_urls (public_number);

create or replace function public.refresh_marketplace_card_urls()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  delete from public.marketplace_card_urls;

  insert into public.marketplace_card_urls (
    card_id,
    language,
    canonical_slug,
    canonical_slug_normalized,
    canonical_path,
    canonical_path_normalized,
    rarity,
    name,
    card_number,
    set_name,
    item_kind,
    product_type,
    is_unique,
    duplicate_group_size,
    duplicate_keys,
    source_projected_at,
    updated_at
  )
  select
    parsed.card_id,
    'en',
    parsed.canonical_slug,
    public.marketplace_search_compact(parsed.canonical_slug),
    parsed.canonical_path,
    lower(parsed.canonical_path),
    parsed.rarity,
    parsed.name,
    parsed.card_number,
    parsed.set_name,
    parsed.item_kind,
    parsed.product_type,
    parsed.duplicate_group_size = 1,
    parsed.duplicate_group_size,
    '[]'::jsonb,
    parsed.projected_at,
    now()
  from (
    select
      source.card_id,
      source.rarity,
      source.name,
      source.card_number,
      source.set_name,
      source.item_kind,
      source.product_type,
      source.projected_at,
      source.canonical_slug,
      '/marketplace/en/cards/' || public.pokoin_public_number(source.card_id)::text
        || '/' || source.canonical_slug as canonical_path,
      count(*) over (partition by source.canonical_slug) as duplicate_group_size
    from (
      select
        c.card_id,
        coalesce(nullif(trim(c.rarity), ''), 'Card') as rarity,
        coalesce(
          nullif(trim(c.display_name), ''),
          nullif(trim(c.canonical_name), ''),
          c.name
        ) as name,
        coalesce(c.card_number, '') as card_number,
        coalesce(nullif(trim(c.set_name), ''), 'Pokemon') as set_name,
        c.item_kind,
        c.product_type,
        c.projected_at,
        coalesce(nullif(trim(both '-' from concat_ws(
          '-',
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.rarity), ''), 'Card')),
          public.marketplace_url_slug_part(coalesce(
            nullif(trim(c.display_name), ''),
            nullif(trim(c.canonical_name), ''),
            c.name
          )),
          public.marketplace_url_slug_part(
            public.marketplace_card_url_collector_number(c.card_number, c.card_id)
          ),
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.set_name), ''), 'Pokemon'))
        )), ''), 'card') as canonical_slug
      from public.marketplace_cards c
      inner join public.marketplace_search_candidates sc
        on sc.card_id = c.card_id
    ) source
  ) parsed;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

comment on function public.refresh_marketplace_card_urls() is
  'Full parse of current CardTrader originals into doubled Pokoin public URL rows.';
