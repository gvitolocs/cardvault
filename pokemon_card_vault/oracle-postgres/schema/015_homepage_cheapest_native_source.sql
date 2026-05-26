comment on column public.cardtrader_blueprint_listing_cache.provider is
  'Winning homepage cheapest source for the blueprint: cardtrader import cache or pokoin_native marketplace listing.';

comment on column public.cardtrader_blueprint_listing_cache.sample_listing_id is
  'External CardTrader listing id or native marketplace_user_listings id for the winning homepage cheapest row.';

drop index if exists public.cardtrader_blueprint_listing_cache_pokoin_available_idx;

create index if not exists cardtrader_blueprint_listing_cache_pokoin_available_idx
  on public.cardtrader_blueprint_listing_cache (pokoin_card_id)
  where provider in ('cardtrader', 'pokoin_native')
    and pokoin_card_id <> ''
    and eligible_listing_count > 0
    and cheapest_price_pkn is not null;

create index if not exists marketplace_user_listings_homepage_native_idx
  on public.marketplace_user_listings (card_id, price_pkn, updated_at desc)
  where status = 'active'
    and quantity_available > 0
    and price_pkn > 0
    and shipping_available = true;
