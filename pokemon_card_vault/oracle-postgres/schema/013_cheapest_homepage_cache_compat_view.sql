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
