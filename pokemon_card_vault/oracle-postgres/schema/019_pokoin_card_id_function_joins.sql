-- Join CardTrader/CDN tables on marketplace_cards.ct_id.
-- marketplace_cards.card_id is our id (ct_id * 2).

CREATE OR REPLACE FUNCTION public.get_marketplace_home_snapshot(result_limit integer DEFAULT 120)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with candidates as (
    select
      c.*,
      coalesce(urls.canonical_path, '') as canonical_path,
      coalesce(
        case
          when lower(nullif(c.rarity, '')) <> 'card' then c.rarity
          else null
        end,
        nullif(b.blueprint->>'rarity', ''),
        nullif(b.blueprint->>'collector_rarity', ''),
        nullif(b.blueprint#>>'{fixed_properties,pokemon_rarity}', ''),
        nullif(c.rarity, ''),
        'Card'
      ) as projected_rarity,
      coalesce(
        nullif(c.card_number, ''),
        nullif(public.marketplace_clean_collector_number(b.version), ''),
        nullif(public.marketplace_clean_collector_number(b.blueprint->>'number'), ''),
        nullif(public.marketplace_clean_collector_number(b.blueprint->>'collector_number'), ''),
        nullif(public.marketplace_clean_collector_number(b.blueprint->>'card_number'), ''),
        nullif(
          replace(
            substring(
              coalesce(c.cdn_image_url, c.image_url, c.homepage_image_url, c.preview_image_url, '')
              from '([0-9]{1,4}[A-Za-z]?[-/][0-9]{1,4})'
            ),
            '-',
            '/'
          ),
          ''
        ),
        c.card_number
      ) as projected_card_number
    from public.marketplace_search_candidates c
    left join public.pokoin_pokemon_blueprints b on b.id = c.ct_id
    left join public.marketplace_card_urls urls
      on urls.card_id = c.card_id
      and urls.language = 'en'
  ),
  scored as (
    select
      c.*,
      coalesce(price_summary.listed_quantity, 0) as listed_quantity,
      price_summary.lowest_ask_pkn as lowest_price_pkn,
      coalesce(h.views_24h, 0) as views_24h,
      coalesce(h.searches_24h, 0) as searches_24h,
      coalesce(h.clicks_24h, 0) as clicks_24h,
      coalesce(h.reserves_24h, 0) as reserves_24h,
      coalesce(h.cart_adds_24h, 0) as cart_adds_24h,
      coalesce(h.sales_24h, 0) as sales_24h,
      coalesce(watchlist_analytics.watchlist_count, 0) as watchlist_count,
      coalesce(cart_analytics.cart_holder_count, 0) as cart_holder_count,
      coalesce(h.hot_score_1h, 0) as hot_score_1h,
      coalesce(h.hot_score_24h, 0) as hot_score_24h,
      coalesce(h.hot_score_7d, 0) as hot_score_7d,
      coalesce((h.metadata->>'cardtraderSales24h')::integer, 0) as cardtrader_sales_24h,
      coalesce((h.metadata->>'cardtraderListingCount')::integer, 0) as cardtrader_listing_count,
      coalesce((h.metadata->>'cardtraderListedQuantity')::integer, 0) as cardtrader_listed_quantity,
      coalesce((h.metadata->>'cardtraderSellThrough7d')::numeric, 0) as cardtrader_sell_through_7d,
      coalesce(cardtrader_cache.eligible_listing_count, 0) as cardtrader_listing_cache_count,
      (
        coalesce(price_summary.listed_quantity, 0) +
        case
          when cardtrader_cache.provider = 'cardtrader' then coalesce(cardtrader_cache.eligible_quantity, 0)
          when coalesce(price_summary.listed_quantity, 0) = 0 then coalesce(cardtrader_cache.eligible_quantity, 0)
          else 0
        end
      ) as available_quantity,
      case
        when cardtrader_cache.cheapest_price_pkn is not null
          and (
            price_summary.lowest_ask_pkn is null
            or cardtrader_cache.cheapest_price_pkn <= price_summary.lowest_ask_pkn
          )
          then cardtrader_cache.cheapest_price_pkn
        else price_summary.lowest_ask_pkn
      end as available_lowest_price_pkn,
      case when cardtrader_cache.provider = 'cardtrader' then coalesce(cardtrader_cache.eligible_listing_count, 0) else 0 end as cardtrader_eligible_listing_count,
      cardtrader_cache.provider = 'cardtrader' and coalesce(cardtrader_cache.eligible_listing_count, 0) > 0 as has_cardtrader_listing,
      case when cardtrader_cache.provider = 'cardtrader' then coalesce(cardtrader_cache.eligible_quantity, 0) else 0 end as cardtrader_eligible_quantity,
      case when cardtrader_cache.provider = 'cardtrader' then cardtrader_cache.cheapest_price_pkn else null end as cardtrader_eligible_lowest_price_pkn,
      case
        when cardtrader_cache.cheapest_price_pkn is not null
          and (
            price_summary.lowest_ask_pkn is null
            or cardtrader_cache.cheapest_price_pkn <= price_summary.lowest_ask_pkn
          )
          then cardtrader_cache.provider
        when price_summary.lowest_ask_pkn is not null then 'pokoin_native'
        else null
      end as homepage_cheapest_provider,
      case
        when cardtrader_cache.cheapest_price_pkn is not null
          and (
            price_summary.lowest_ask_pkn is null
            or cardtrader_cache.cheapest_price_pkn <= price_summary.lowest_ask_pkn
          )
          then case
            when cardtrader_cache.provider = 'pokoin_native' then 'pokoin_native_homepage_cache'
            else 'cheapest_homepage_cache_blueprint'
          end
        when price_summary.lowest_ask_pkn is not null then 'marketplace_blueprint_price_summary'
        else null
      end as homepage_cheapest_source,
      cardtrader_cache.sample_listing_id as homepage_cheapest_listing_id,
      (
        coalesce(h.hot_score_1h, 0) * 1.8 +
        coalesce(h.hot_score_24h, 0) +
        coalesce(h.hot_score_7d, 0) * 0.12 +
        coalesce((h.metadata->>'cardtraderSales24h')::integer, 0) * 3 +
        coalesce((h.metadata->>'cardtraderListedQuantity')::integer, 0) * 0.05 +
        coalesce((h.metadata->>'cardtraderSellThrough7d')::numeric, 0) * 8 +
        case when c.projected_rarity ilike '%holo%' or c.projected_rarity ilike '%rare%' then 5 else 0 end +
        c.search_weight
      )::numeric as spotlight_score
    from candidates c
    left join public.marketplace_hot_blueprints h on h.blueprint_id = c.ct_id
    left join public.marketplace_card_watchlist_analytics watchlist_analytics
      on watchlist_analytics.blueprint_id = c.ct_id
    left join public.marketplace_card_cart_analytics cart_analytics
      on cart_analytics.blueprint_id = c.ct_id
    left join public.marketplace_blueprint_price_summary price_summary
      on price_summary.blueprint_id = c.ct_id
    left join lateral (
      select cache.*
      from public.cheapest_homepage_cache_blueprint cache
      where cache.provider in ('cardtrader', 'pokoin_native')
        and cache.eligible_listing_count > 0
        and cache.cheapest_price_pkn is not null
        and (
          cache.blueprint_id = c.ct_id
          or cache.pokoin_card_id = c.card_id::text
        )
      order by
        case when cache.blueprint_id = c.ct_id then 0 else 1 end,
        cache.cheapest_price_pkn asc,
        case when cache.provider = 'pokoin_native' then 0 else 1 end,
        cache.eligible_listing_count desc,
        cache.blueprint_id asc,
        cache.provider asc
      limit 1
    ) cardtrader_cache on true
  ),
  cards as (
    select *
    from scored
    order by spotlight_score desc, imported_at desc nulls last, card_id desc
    limit greatest(1, least(result_limit, 500))
  ),
  recent_ids as (
    select coalesce(jsonb_agg(card_id::text order by imported_at desc nulls last, card_id desc), '[]'::jsonb) ids
    from (select * from scored order by imported_at desc nulls last, card_id desc limit 12) r
  ),
  spotlight_ids as (
    select coalesce(jsonb_agg(card_id::text order by spotlight_score desc, imported_at desc nulls last), '[]'::jsonb) ids
    from (select * from scored order by spotlight_score desc, imported_at desc nulls last limit 12) s
  ),
  featured_pool as (
    select *
    from (
      select
        scored.*,
        row_number() over (
          order by spotlight_score desc, imported_at desc nulls last, card_id desc
        )::integer as pool_rank
      from scored
      where projected_rarity ilike '%rare%'
         or projected_rarity ilike '%promo%'
         or name ~* '(^|[^a-z0-9])(ex|vmax|vstar|gx|lv\.x)([^a-z0-9]|$)'
    ) ranked_featured
    where pool_rank <= 36
  ),
  featured_ids as (
    select coalesce(jsonb_agg(card_id::text order by rotated_rank, pool_rank), '[]'::jsonb) ids
    from (
      select
        card_id,
        pool_rank,
        (
          (
            pool_rank - 1 + greatest((select count(*) from featured_pool), 1) -
            ((floor(extract(epoch from now()) / 21600)::integer % 6) * 6)
          ) % greatest((select count(*) from featured_pool), 1)
        ) as rotated_rank
      from featured_pool
      order by rotated_rank, pool_rank
      limit 12
    ) rotated
  )
  select jsonb_build_object(
    'generatedAt', now(),
    'cards', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', card_id::text,
          'canonicalPath', canonical_path,
          'canonical_path', canonical_path,
          'name', name,
          'imageUrl', coalesce(cdn_image_url, image_url, ''),
          'previewImageUrl', coalesce(preview_image_url, cdn_image_url, image_url, ''),
          'homepageImageUrl', coalesce(homepage_image_url, preview_image_url, cdn_image_url, image_url, ''),
          'rarity', projected_rarity,
          'type', card_type,
          'set', set_name,
          'number', projected_card_number,
          'card_number', projected_card_number,
          'expansion_number', projected_card_number,
          'itemKind', case when projected_card_number ~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}' then 'single' else item_kind end,
          'productType', case when projected_card_number ~ '[0-9]{1,4}[A-Za-z]?/[0-9]{1,4}' then 'card' else product_type end,
          'trainerName', trainer_name,
          'cardPalette', card_palette,
          'emoji', emoji,
          'price', available_lowest_price_pkn,
          'priceSource', homepage_cheapest_source,
          'homepageCheapestProvider', homepage_cheapest_provider,
          'homepageCheapestListingId', homepage_cheapest_listing_id,
          'stock', available_quantity,
          'rating', watchlist_count,
          'cartHolderCount', cart_holder_count,
          'reviewCount', 0,
          'isFoil', false,
          'isHolo', projected_rarity ilike '%holo%',
          'tags', to_jsonb(array_remove(array[set_name, projected_rarity, card_type, trainer_name], '')),
          'condition', 'NM',
          'isGraded', false,
          'hasCardTraderListing', has_cardtrader_listing,
          'cardtraderEligibleListingCount', cardtrader_eligible_listing_count,
          'cardtraderListedQuantity', cardtrader_eligible_quantity,
          'cardtraderLowestPricePkn', cardtrader_eligible_lowest_price_pkn,
          'analytics', jsonb_build_object(
            'views24h', views_24h,
            'searches24h', searches_24h,
            'clicks24h', clicks_24h,
            'reserves24h', reserves_24h,
            'cartAdds24h', cart_adds_24h,
            'sales24h', sales_24h,
            'watchlistCount', watchlist_count,
            'cartHolderCount', cart_holder_count,
            'cardtraderSales24h', cardtrader_sales_24h,
            'cardtraderListingCount', greatest(cardtrader_listing_count, cardtrader_listing_cache_count),
            'cardtraderEligibleListingCount', cardtrader_eligible_listing_count,
            'cardtraderListedQuantity', greatest(cardtrader_listed_quantity, cardtrader_eligible_quantity),
            'cardtraderSellThrough7d', cardtrader_sell_through_7d,
            'hotScore1h', hot_score_1h,
            'hotScore24h', hot_score_24h,
            'hotScore7d', hot_score_7d,
            'spotlightScore', spotlight_score
          )
        )
        order by spotlight_score desc, imported_at desc nulls last, card_id desc
      ),
      '[]'::jsonb
    ),
    'sections', jsonb_build_object(
      'recentlySeenIds', (select ids from recent_ids),
      'bestSellerIds', (select ids from spotlight_ids),
      'featuredIds', (select ids from featured_ids)
    )
  )
  from cards;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_marketplace_hot_blueprints()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  refreshed_count integer;
begin
  delete from public.marketplace_hot_blueprints;

  insert into public.marketplace_hot_blueprints (
    blueprint_id,
    name,
    set_name,
    card_number,
    rarity,
    card_type,
    item_kind,
    product_type,
    views_1h,
    searches_1h,
    clicks_1h,
    cart_adds_1h,
    reserves_1h,
    sales_1h,
    hot_score_1h,
    views_24h,
    searches_24h,
    clicks_24h,
    cart_adds_24h,
    reserves_24h,
    sales_24h,
    hot_score_24h,
    views_7d,
    searches_7d,
    clicks_7d,
    cart_adds_7d,
    reserves_7d,
    sales_7d,
    hot_score_7d,
    last_event_at,
    metadata,
    refreshed_at
  )
  with event_rollup as (
    select
      event.ct_id as blueprint_id,
      count(*) filter (where event.event_type = 'view' and event.occurred_at >= now() - interval '1 hour')::integer as views_1h,
      count(*) filter (where event.event_type = 'search' and event.occurred_at >= now() - interval '1 hour')::integer as searches_1h,
      count(*) filter (where event.event_type = 'click' and event.occurred_at >= now() - interval '1 hour')::integer as clicks_1h,
      count(*) filter (where event.event_type = 'cart_add' and event.occurred_at >= now() - interval '1 hour')::integer as cart_adds_1h,
      count(*) filter (where event.event_type = 'reserve' and event.occurred_at >= now() - interval '1 hour')::integer as reserves_1h,
      count(*) filter (where event.event_type = 'sale' and event.occurred_at >= now() - interval '1 hour')::integer as sales_1h,
      coalesce(sum(event.weight) filter (where event.occurred_at >= now() - interval '1 hour'), 0)::numeric as hot_score_1h,
      count(*) filter (where event.event_type = 'view' and event.occurred_at >= now() - interval '24 hours')::integer as views_24h,
      count(*) filter (where event.event_type = 'search' and event.occurred_at >= now() - interval '24 hours')::integer as searches_24h,
      count(*) filter (where event.event_type = 'click' and event.occurred_at >= now() - interval '24 hours')::integer as clicks_24h,
      count(*) filter (where event.event_type = 'cart_add' and event.occurred_at >= now() - interval '24 hours')::integer as cart_adds_24h,
      count(*) filter (where event.event_type = 'reserve' and event.occurred_at >= now() - interval '24 hours')::integer as reserves_24h,
      count(*) filter (where event.event_type = 'sale' and event.occurred_at >= now() - interval '24 hours')::integer as sales_24h,
      coalesce(sum(event.weight) filter (where event.occurred_at >= now() - interval '24 hours'), 0)::numeric as hot_score_24h,
      count(*) filter (where event.event_type = 'view' and event.occurred_at >= now() - interval '7 days')::integer as views_7d,
      count(*) filter (where event.event_type = 'search' and event.occurred_at >= now() - interval '7 days')::integer as searches_7d,
      count(*) filter (where event.event_type = 'click' and event.occurred_at >= now() - interval '7 days')::integer as clicks_7d,
      count(*) filter (where event.event_type = 'cart_add' and event.occurred_at >= now() - interval '7 days')::integer as cart_adds_7d,
      count(*) filter (where event.event_type = 'reserve' and event.occurred_at >= now() - interval '7 days')::integer as reserves_7d,
      count(*) filter (where event.event_type = 'sale' and event.occurred_at >= now() - interval '7 days')::integer as sales_7d,
      coalesce(sum(event.weight) filter (where event.occurred_at >= now() - interval '7 days'), 0)::numeric as hot_score_7d,
      max(event.occurred_at) as last_event_at
    from public.marketplace_card_events event
    where event.occurred_at >= now() - interval '7 days'
    group by event.ct_id
  ),
  cardtrader_rollup as (
    select
      analytics.blueprint_id,
      coalesce(sum(analytics.sold_count) filter (where analytics.observed_day >= current_date - 1), 0)::integer as ct_sales_24h,
      coalesce(sum(analytics.sold_count) filter (where analytics.observed_day >= current_date - 7), 0)::integer as ct_sales_7d,
      coalesce(avg(analytics.sell_through_rate) filter (where analytics.observed_day >= current_date - 7), 0)::numeric as ct_sell_through_7d,
      coalesce(max(analytics.listed_quantity), 0)::integer as ct_listed_quantity,
      coalesce(max(analytics.listing_count), 0)::integer as ct_listing_count,
      max(analytics.refreshed_at) as ct_refreshed_at
    from public.cardtrader_blueprint_daily_analytics analytics
    where analytics.observed_day >= current_date - 7
    group by analytics.blueprint_id
  ),
  combined as (
    select
      c.ct_id as blueprint_id,
      c.name,
      c.set_name,
      c.card_number,
      c.rarity,
      c.card_type,
      c.item_kind,
      c.product_type,
      coalesce(e.views_1h, 0) as views_1h,
      coalesce(e.searches_1h, 0) as searches_1h,
      coalesce(e.clicks_1h, 0) as clicks_1h,
      coalesce(e.cart_adds_1h, 0) as cart_adds_1h,
      coalesce(e.reserves_1h, 0) as reserves_1h,
      coalesce(e.sales_1h, 0) as sales_1h,
      coalesce(e.hot_score_1h, 0) as base_hot_score_1h,
      coalesce(e.views_24h, 0) as views_24h,
      coalesce(e.searches_24h, 0) as searches_24h,
      coalesce(e.clicks_24h, 0) as clicks_24h,
      coalesce(e.cart_adds_24h, 0) as cart_adds_24h,
      coalesce(e.reserves_24h, 0) as reserves_24h,
      coalesce(e.sales_24h, 0) + coalesce(ct.ct_sales_24h, 0) as sales_24h,
      coalesce(e.hot_score_24h, 0) as base_hot_score_24h,
      coalesce(e.views_7d, 0) as views_7d,
      coalesce(e.searches_7d, 0) as searches_7d,
      coalesce(e.clicks_7d, 0) as clicks_7d,
      coalesce(e.cart_adds_7d, 0) as cart_adds_7d,
      coalesce(e.reserves_7d, 0) as reserves_7d,
      coalesce(e.sales_7d, 0) + coalesce(ct.ct_sales_7d, 0) as sales_7d,
      coalesce(e.hot_score_7d, 0) as base_hot_score_7d,
      greatest(
        coalesce(e.last_event_at, timestamp with time zone 'epoch'),
        coalesce(ct.ct_refreshed_at, timestamp with time zone 'epoch')
      ) as last_event_at,
      coalesce(ct.ct_sales_24h, 0) as ct_sales_24h,
      coalesce(ct.ct_sales_7d, 0) as ct_sales_7d,
      coalesce(ct.ct_sell_through_7d, 0) as ct_sell_through_7d,
      coalesce(ct.ct_listed_quantity, 0) as ct_listed_quantity,
      coalesce(ct.ct_listing_count, 0) as ct_listing_count,
      ct.ct_refreshed_at
    from public.marketplace_search_candidates c
    left join event_rollup e on e.blueprint_id = c.ct_id
    left join cardtrader_rollup ct on ct.blueprint_id = c.ct_id
    where e.blueprint_id is not null or ct.blueprint_id is not null
  )
  select
    blueprint_id,
    name,
    set_name,
    card_number,
    rarity,
    card_type,
    item_kind,
    product_type,
    views_1h,
    searches_1h,
    clicks_1h,
    cart_adds_1h,
    reserves_1h,
    sales_1h,
    base_hot_score_1h,
    views_24h,
    searches_24h,
    clicks_24h,
    cart_adds_24h,
    reserves_24h,
    sales_24h,
    (
      base_hot_score_24h +
      ct_sales_24h * 22 +
      ct_listed_quantity * 0.15 +
      ct_sell_through_7d * 30
    )::numeric,
    views_7d,
    searches_7d,
    clicks_7d,
    cart_adds_7d,
    reserves_7d,
    sales_7d,
    (
      base_hot_score_7d +
      ct_sales_7d * 18 +
      ct_listed_quantity * 0.08 +
      ct_sell_through_7d * 20
    )::numeric,
    last_event_at,
    jsonb_build_object(
      'cardtraderSales24h', ct_sales_24h,
      'cardtraderSales7d', ct_sales_7d,
      'cardtraderListingCount', ct_listing_count,
      'cardtraderListedQuantity', ct_listed_quantity,
      'cardtraderSellThrough7d', ct_sell_through_7d,
      'cardtraderRefreshedAt', ct_refreshed_at
    ),
    now()
  from combined;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$function$;
