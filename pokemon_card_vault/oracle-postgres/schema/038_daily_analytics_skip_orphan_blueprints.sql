-- CardTrader expansion responses can contain marketplace products whose
-- blueprint ids are not present in the local Pokemon blueprint catalog.
-- Keep those rows in the raw snapshot, but do not let them violate the
-- daily analytics FK and abort finalization for every valid card.

create or replace function public.refresh_cardtrader_blueprint_daily_analytics(
  target_day date default current_date - 1
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
  v_day date := coalesce(target_day, current_date - 1);
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '4s', true);

  delete from public.cardtrader_blueprint_daily_analytics
  where observed_day = v_day;

  insert into public.cardtrader_blueprint_daily_analytics (
    observed_day,
    blueprint_id,
    listing_count,
    listed_quantity,
    seller_count,
    sold_count,
    sold_quantity,
    min_price_pkn,
    median_price_pkn,
    average_price_pkn,
    max_price_pkn,
    previous_min_price_pkn,
    price_change_pct,
    sell_through_rate,
    source_counts,
    refreshed_at
  )
  with listed as (
    select
      pop.blueprint_id,
      coalesce(pop.listing_count, 0)::integer as listing_count,
      coalesce(pop.listed_quantity, 0)::integer as listed_quantity,
      coalesce(pop.seller_count, 0)::integer as seller_count,
      cache.cheapest_price_pkn as min_price_pkn,
      cache.cheapest_price_pkn as median_price_pkn,
      cache.cheapest_price_pkn as average_price_pkn,
      cache.cheapest_price_pkn as max_price_pkn
    from public.cardtrader_blueprint_population_daily pop
    left join public.cardtrader_blueprint_listing_cache cache
      on cache.blueprint_id = pop.blueprint_id
    where pop.observed_day = (timezone('utc', now()))::date
      and pop.blueprint_id is not null
  ),
  removed as (
    select
      coalesce(history.blueprint_id, history.cardtrader_blueprint_id) as blueprint_id,
      count(*)::integer as sold_count,
      coalesce(sum(history.quantity), 0)::integer as sold_quantity
    from public.cardtrader_market_listing_removed_history history
    where history.removed_day = v_day
      and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
      and public.cardtrader_market_is_sale_reason(history.archive_reason)
    group by 1
  ),
  previous_day as (
    select distinct on (blueprint_id)
      blueprint_id,
      min_price_pkn
    from public.cardtrader_blueprint_daily_analytics
    where observed_day < v_day
    order by blueprint_id, observed_day desc
  ),
  combined as (
    select
      coalesce(listed.blueprint_id, removed.blueprint_id) as blueprint_id,
      coalesce(listed.listing_count, 0) as listing_count,
      coalesce(listed.listed_quantity, 0) as listed_quantity,
      coalesce(listed.seller_count, 0) as seller_count,
      coalesce(removed.sold_count, 0) as sold_count,
      coalesce(removed.sold_quantity, 0) as sold_quantity,
      listed.min_price_pkn,
      listed.median_price_pkn,
      listed.average_price_pkn,
      listed.max_price_pkn,
      previous_day.min_price_pkn as previous_min_price_pkn
    from listed
    full outer join removed on removed.blueprint_id = listed.blueprint_id
    left join previous_day
      on previous_day.blueprint_id = coalesce(listed.blueprint_id, removed.blueprint_id)
  )
  select
    v_day,
    combined.blueprint_id,
    combined.listing_count,
    combined.listed_quantity,
    combined.seller_count,
    combined.sold_count,
    combined.sold_quantity,
    combined.min_price_pkn,
    combined.median_price_pkn,
    combined.average_price_pkn,
    combined.max_price_pkn,
    combined.previous_min_price_pkn,
    case
      when combined.previous_min_price_pkn > 0 and combined.min_price_pkn is not null
      then (combined.min_price_pkn - combined.previous_min_price_pkn) / combined.previous_min_price_pkn
      else null
    end,
    case
      when combined.sold_quantity + combined.listed_quantity > 0
      then combined.sold_quantity::numeric / (combined.sold_quantity + combined.listed_quantity)
      else 0
    end,
    jsonb_build_object(
      'cardtrader_market_cache', combined.listing_count,
      'cardtrader_market_removed', combined.sold_count
    ),
    now()
  from combined
  where combined.blueprint_id is not null
    and exists (
      select 1
      from public.cardtrader_pokemon_blueprints blueprints
      where blueprints.id = combined.blueprint_id
    );

  get diagnostics refreshed_count = row_count;
  return coalesce(refreshed_count, 0);
end;
$$;
