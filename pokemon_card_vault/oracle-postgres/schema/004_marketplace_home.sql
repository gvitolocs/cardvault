create or replace function public.get_marketplace_home_snapshot(result_limit integer default 120)
returns jsonb
language sql
stable
set search_path = public
as $$
  with recent_events as (
    select
      card_id,
      count(*) filter (where event_type = 'view') as views_24h,
      count(*) filter (where event_type = 'search') as searches_24h,
      count(*) filter (where event_type = 'click') as clicks_24h,
      count(*) filter (where event_type = 'reserve') as reserves_24h,
      count(*) filter (where event_type = 'cart_add') as cart_adds_24h,
      count(*) filter (where event_type = 'sale') as sales_24h,
      coalesce(sum(weight), 0) as weighted_events_24h
    from public.marketplace_card_events
    where occurred_at >= now() - interval '24 hours'
    group by card_id
  ),
  scored as (
    select
      c.*,
      coalesce(e.views_24h, 0) as views_24h,
      coalesce(e.searches_24h, 0) as searches_24h,
      coalesce(e.clicks_24h, 0) as clicks_24h,
      coalesce(e.reserves_24h, 0) as reserves_24h,
      coalesce(e.cart_adds_24h, 0) as cart_adds_24h,
      coalesce(e.sales_24h, 0) as sales_24h,
      (
        coalesce(e.views_24h, 0) * 1 +
        coalesce(e.searches_24h, 0) * 2 +
        coalesce(e.clicks_24h, 0) * 4 +
        coalesce(e.cart_adds_24h, 0) * 8 +
        coalesce(e.reserves_24h, 0) * 10 +
        coalesce(e.sales_24h, 0) * 20 +
        case when c.rarity ilike '%holo%' or c.rarity ilike '%rare%' then 5 else 0 end +
        c.search_weight
      )::numeric as spotlight_score
    from public.marketplace_search_candidates c
    left join recent_events e on e.card_id = c.card_id
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
  featured_ids as (
    select coalesce(jsonb_agg(card_id::text order by rarity desc, imported_at desc nulls last), '[]'::jsonb) ids
    from (
      select *
      from scored
      where rarity ilike '%rare%' or rarity ilike '%promo%' or name ~* '(^|[^a-z0-9])(ex|vmax|vstar|gx|lv\.x)([^a-z0-9]|$)'
      order by rarity desc, imported_at desc nulls last
      limit 12
    ) f
  )
  select jsonb_build_object(
    'generatedAt', now(),
    'cards', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', card_id::text,
          'name', name,
          'imageUrl', coalesce(cdn_image_url, image_url, ''),
          'previewImageUrl', coalesce(preview_image_url, cdn_image_url, image_url, ''),
          'rarity', rarity,
          'type', card_type,
          'set', set_name,
          'number', card_number,
          'itemKind', item_kind,
          'productType', product_type,
          'trainerName', trainer_name,
          'cardPalette', card_palette,
          'emoji', emoji,
          'price', (1000 + (card_id % 120000)),
          'stock', 0,
          'rating', 0,
          'reviewCount', 0,
          'isFoil', false,
          'isHolo', rarity ilike '%holo%',
          'tags', to_jsonb(array_remove(array[set_name, rarity, card_type, trainer_name], '')),
          'condition', 'NM',
          'isGraded', false,
          'analytics', jsonb_build_object(
            'views24h', views_24h,
            'searches24h', searches_24h,
            'clicks24h', clicks_24h,
            'reserves24h', reserves_24h,
            'cartAdds24h', cart_adds_24h,
            'sales24h', sales_24h,
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

