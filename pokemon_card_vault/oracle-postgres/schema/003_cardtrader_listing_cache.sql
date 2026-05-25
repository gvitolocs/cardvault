create table if not exists public.cardtrader_blueprint_listing_cache (
  provider text not null default 'cardtrader',
  blueprint_id bigint not null primary key,
  pokoin_card_id text not null default '',
  cheapest_price_eur numeric,
  cheapest_price_pkn numeric,
  eligible_listing_count integer not null default 0 check (eligible_listing_count >= 0),
  eligible_quantity integer not null default 0 check (eligible_quantity >= 0),
  sample_listing_id text not null default '',
  sample_product_id text not null default '',
  shipping_mode text not null default '',
  seller_country_code text not null default '',
  source_snapshot_at timestamptz,
  updated_at timestamptz not null default now()
);

create or replace view public.cheapest_homepage_cache_blueprint as
select
  provider,
  blueprint_id,
  pokoin_card_id,
  cheapest_price_eur,
  cheapest_price_pkn,
  eligible_listing_count,
  eligible_quantity,
  sample_listing_id,
  sample_product_id,
  shipping_mode,
  seller_country_code,
  source_snapshot_at,
  updated_at
from public.cardtrader_blueprint_listing_cache;

create index if not exists cardtrader_blueprint_listing_cache_provider_updated_idx
  on public.cardtrader_blueprint_listing_cache (provider, updated_at desc);

create index if not exists cardtrader_blueprint_listing_cache_available_idx
  on public.cardtrader_blueprint_listing_cache (blueprint_id)
  where eligible_listing_count > 0 and cheapest_price_pkn is not null;

create index if not exists cardtrader_blueprint_listing_cache_pokoin_available_idx
  on public.cardtrader_blueprint_listing_cache (pokoin_card_id)
  where provider = 'cardtrader'
    and pokoin_card_id <> ''
    and eligible_listing_count > 0
    and cheapest_price_pkn is not null;
