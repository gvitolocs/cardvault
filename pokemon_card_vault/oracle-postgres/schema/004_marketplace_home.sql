create or replace function public.get_marketplace_home_snapshot(result_limit integer default 120)
returns jsonb
language sql
stable
set search_path = public
as $$
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
    left join public.cardtrader_pokemon_blueprints b on b.id = c.card_id
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
        coalesce(cardtrader_cache.eligible_listing_count, 0)
      ) as available_quantity,
      case
        when cardtrader_cache.cheapest_price_pkn is not null then cardtrader_cache.cheapest_price_pkn
        else price_summary.lowest_ask_pkn
      end as available_lowest_price_pkn,
      coalesce(cardtrader_cache.eligible_listing_count, 0) as cardtrader_eligible_listing_count,
      coalesce(cardtrader_cache.eligible_listing_count, 0) > 0 as has_cardtrader_listing,
      coalesce(cardtrader_cache.eligible_quantity, 0) as cardtrader_eligible_quantity,
      cardtrader_cache.cheapest_price_pkn as cardtrader_eligible_lowest_price_pkn,
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
    left join public.marketplace_hot_blueprints h on h.blueprint_id = c.card_id
    left join public.marketplace_card_watchlist_analytics watchlist_analytics
      on watchlist_analytics.blueprint_id = c.card_id
    left join public.marketplace_card_cart_analytics cart_analytics
      on cart_analytics.blueprint_id = c.card_id
    left join public.marketplace_blueprint_price_summary price_summary
      on price_summary.blueprint_id = c.card_id
    left join lateral (
      select cache.*
      from public.cheapest_homepage_cache_blueprint cache
      where cache.provider = 'cardtrader'
        and cache.eligible_listing_count > 0
        and cache.cheapest_price_pkn is not null
        and (
          cache.blueprint_id = c.card_id
          or cache.pokoin_card_id = c.card_id::text
        )
      order by
        case when cache.blueprint_id = c.card_id then 0 else 1 end,
        cache.cheapest_price_pkn asc,
        cache.eligible_listing_count desc,
        cache.blueprint_id asc
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
          'price', coalesce(available_lowest_price_pkn, (1000 + (card_id % 120000))::numeric),
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
$$;

