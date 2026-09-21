-- Remove erroneous +200 shipping pad from CardTrader market-reference PKN.
-- cheapest_price_pkn must match the daily dump conversion: EUR / 0.005 only.
-- Shipping fees (if charged) stay outside the market reference column.

create or replace function public.refresh_cardtrader_blueprint_listing_cache(
  p_provider text default 'cardtrader',
  p_scope_blueprint_ids jsonb default '[]'::jsonb,
  p_refreshed_at timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer := 0;
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_scope_blueprint_ids jsonb := coalesce(p_scope_blueprint_ids, '[]'::jsonb);
  v_has_scope boolean := false;
begin
  if jsonb_typeof(v_scope_blueprint_ids) <> 'array' then
    raise exception 'scope blueprint ids must be a JSONB array';
  end if;

  create temp table if not exists pg_temp.cardtrader_blueprint_listing_cache_scope (
    blueprint_id bigint primary key
  ) on commit drop;

  create temp table if not exists pg_temp.cardtrader_blueprint_listing_cache_refresh (
    provider text not null,
    blueprint_id bigint primary key,
    pokoin_card_id text not null,
    cheapest_price_eur numeric,
    cheapest_price_pkn numeric,
    eligible_listing_count integer not null,
    eligible_quantity integer not null,
    sample_listing_id text not null,
    sample_product_id text not null,
    shipping_mode text not null,
    seller_country_code text not null,
    source_snapshot_at timestamptz,
    updated_at timestamptz not null
  ) on commit drop;

  truncate table pg_temp.cardtrader_blueprint_listing_cache_scope;
  truncate table pg_temp.cardtrader_blueprint_listing_cache_refresh;

  insert into pg_temp.cardtrader_blueprint_listing_cache_scope (blueprint_id)
  select distinct value::bigint
  from jsonb_array_elements_text(v_scope_blueprint_ids) as scope(value)
  where value ~ '^[0-9]+$'
  on conflict do nothing;

  select exists (select 1 from pg_temp.cardtrader_blueprint_listing_cache_scope)
  into v_has_scope;

  insert into pg_temp.cardtrader_blueprint_listing_cache_refresh (
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
  )
  with eligible_cardtrader as (
    select
      snapshot.provider,
      coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id) as blueprint_id,
      snapshot.pokoin_card_id,
      snapshot.external_listing_id,
      snapshot.external_product_id,
      case
        when upper(coalesce(nullif(snapshot.currency, ''), 'EUR')) = 'EUR'
        then coalesce(snapshot.price, snapshot.price_cents::numeric / 100)
        else null
      end as price_eur,
      public.marketplace_price_pkn_from_cardtrader(
        snapshot.price,
        snapshot.price_cents,
        snapshot.currency
      ) as price_pkn,
      snapshot.quantity,
      case
        when lower(coalesce(snapshot.properties->>'shipping_mode', '')) = 'one_day_ready'
          or lower(coalesce(snapshot.seller_account_name, '')) ~ '1[[:space:]-]*day[[:space:]-]*ready'
        then 'one_day_ready'
        else 'zero'
      end as shipping_mode,
      snapshot.seller_country,
      snapshot.last_seen_at,
      snapshot.updated_at
    from public.cardtrader_market_listing_snapshots snapshot
    left join pg_temp.cardtrader_blueprint_listing_cache_scope scope
      on scope.blueprint_id = coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id)
    where snapshot.provider = v_provider
      and coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id) is not null
      and (not v_has_scope or scope.blueprint_id is not null)
      and coalesce(snapshot.quantity, 0) > 0
      and upper(coalesce(nullif(snapshot.currency, ''), 'EUR')) = 'EUR'
      and public.marketplace_price_pkn_from_cardtrader(
        snapshot.price,
        snapshot.price_cents,
        snapshot.currency
      ) is not null
      and (
        lower(coalesce(snapshot.raw_metadata->'user'->>'can_sell_via_hub', snapshot.raw_metadata->>'can_sell_via_hub', '')) in ('true', '1', 'yes', 'y')
        or lower(coalesce(snapshot.raw_metadata->'user'->>'can_sell_sealed_with_ct_zero', snapshot.raw_metadata->>'can_sell_sealed_with_ct_zero', '')) in ('true', '1', 'yes', 'y')
        or lower(coalesce(snapshot.properties->>'shipping_mode', '')) = 'one_day_ready'
        or lower(coalesce(snapshot.seller_account_name, '')) ~ '1[[:space:]-]*day[[:space:]-]*ready'
      )
  ),
  eligible_native as (
    select
      'pokoin_native'::text as provider,
      native_listing.card_id::bigint as blueprint_id,
      native_listing.card_id::text as pokoin_card_id,
      native_listing.id::text as external_listing_id,
      left(coalesce(nullif(native_listing.source_listing_id, ''), native_listing.id::text), 160) as external_product_id,
      null::numeric as price_eur,
      native_listing.price_pkn as price_pkn,
      native_listing.quantity_available as quantity,
      'pokoin_native'::text as shipping_mode,
      native_listing.seller_country,
      native_listing.updated_at as last_seen_at,
      native_listing.updated_at
    from (
      select
        listing.*,
        case when listing.card_id ~ '^[0-9]+$' then listing.card_id::bigint else null end as card_id_bigint
      from public.marketplace_user_listings
      listing
    ) native_listing
    left join pg_temp.cardtrader_blueprint_listing_cache_scope scope
      on scope.blueprint_id = native_listing.card_id_bigint
    where native_listing.card_id_bigint is not null
      and (not v_has_scope or scope.blueprint_id is not null)
      and native_listing.status = 'active'
      and coalesce(native_listing.quantity_available, 0) > 0
      and native_listing.price_pkn > 0
      and coalesce(native_listing.shipping_available, true) = true
      and not (
        native_listing.nft_available = true
        and coalesce(native_listing.shipping_available, false) = false
      )
  ),
  eligible as (
    select * from eligible_cardtrader
    union all
    select * from eligible_native
  ),
  ranked as (
    select
      eligible.*,
      count(*) over (partition by eligible.blueprint_id, eligible.provider)::integer as eligible_listing_count,
      coalesce(sum(eligible.quantity) over (partition by eligible.blueprint_id, eligible.provider), 0)::integer as eligible_quantity,
      max(eligible.last_seen_at) over (partition by eligible.blueprint_id, eligible.provider) as source_snapshot_at,
      row_number() over (
        partition by eligible.blueprint_id
        order by
          eligible.price_pkn asc,
          case when eligible.provider = 'pokoin_native' then 0 else 1 end,
          eligible.last_seen_at desc,
          eligible.external_listing_id asc
      ) as price_rank
    from eligible
  )
  select
    ranked.provider,
    ranked.blueprint_id,
    left(coalesce(nullif(ranked.pokoin_card_id, ''), (ranked.blueprint_id * 2)::text), 80),
    ranked.price_eur,
    ranked.price_pkn,
    ranked.eligible_listing_count,
    ranked.eligible_quantity,
    left(ranked.external_listing_id, 160),
    left(ranked.external_product_id, 160),
    ranked.shipping_mode,
    left(coalesce(ranked.seller_country, ''), 40),
    ranked.source_snapshot_at,
    p_refreshed_at
  from ranked
  where ranked.price_rank = 1;

  select count(*)::integer
  from pg_temp.cardtrader_blueprint_listing_cache_refresh
  into refreshed_count;

  insert into public.cardtrader_blueprint_listing_cache (
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
  )
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
  from pg_temp.cardtrader_blueprint_listing_cache_refresh
  on conflict (blueprint_id) do update set
    provider = excluded.provider,
    pokoin_card_id = excluded.pokoin_card_id,
    cheapest_price_eur = excluded.cheapest_price_eur,
    cheapest_price_pkn = excluded.cheapest_price_pkn,
    eligible_listing_count = excluded.eligible_listing_count,
    eligible_quantity = excluded.eligible_quantity,
    sample_listing_id = excluded.sample_listing_id,
    sample_product_id = excluded.sample_product_id,
    shipping_mode = excluded.shipping_mode,
    seller_country_code = excluded.seller_country_code,
    source_snapshot_at = excluded.source_snapshot_at,
    updated_at = excluded.updated_at;

  delete from public.cardtrader_blueprint_listing_cache cache
  where cache.provider in (v_provider, 'pokoin_native')
    and (
      not v_has_scope
      or exists (
        select 1
        from pg_temp.cardtrader_blueprint_listing_cache_scope scope
        where scope.blueprint_id = cache.blueprint_id
      )
    )
    and not exists (
      select 1
      from pg_temp.cardtrader_blueprint_listing_cache_refresh refreshed
      where refreshed.blueprint_id = cache.blueprint_id
    );

  return refreshed_count;
end;
$$;
