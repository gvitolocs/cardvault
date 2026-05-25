create table if not exists public.cardtrader_user_listing_snapshots (
  provider text not null default 'cardtrader',
  seller_uid text not null,
  seller_account_id text not null default '',
  seller_account_name text not null default '',
  external_listing_id text not null,
  external_product_id text not null default '',
  blueprint_id bigint,
  cardtrader_blueprint_id bigint,
  pokoin_card_id text not null default '',
  quantity integer not null default 0 check (quantity >= 0),
  condition text not null default '',
  language text not null default '',
  price numeric,
  price_cents integer,
  currency text not null default '',
  properties jsonb not null default '{}'::jsonb,
  raw_metadata jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, seller_uid, external_listing_id)
);

alter table public.cardtrader_user_listing_snapshots
  add column if not exists external_product_id text not null default '';

alter table public.cardtrader_user_listing_snapshots
  add column if not exists seller_account_id text not null default '';

alter table public.cardtrader_user_listing_snapshots
  add column if not exists seller_account_name text not null default '';

alter table public.cardtrader_user_listing_snapshots
  add column if not exists cardtrader_blueprint_id bigint;

alter table public.cardtrader_user_listing_snapshots
  add column if not exists pokoin_card_id text not null default '';

create index if not exists cardtrader_user_listing_snapshots_blueprint_idx
  on public.cardtrader_user_listing_snapshots (
    coalesce(blueprint_id, cardtrader_blueprint_id),
    last_seen_at desc
  );

create index if not exists cardtrader_user_listing_snapshots_seller_idx
  on public.cardtrader_user_listing_snapshots (seller_uid, last_seen_at desc);

create index if not exists cardtrader_user_listing_snapshots_product_idx
  on public.cardtrader_user_listing_snapshots (provider, external_product_id)
  where external_product_id <> '';

create table if not exists public.cardtrader_user_listing_removed_history (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'cardtrader',
  seller_uid text not null,
  seller_account_id text not null default '',
  seller_account_name text not null default '',
  external_listing_id text not null,
  external_product_id text not null default '',
  blueprint_id bigint,
  cardtrader_blueprint_id bigint,
  pokoin_card_id text not null default '',
  quantity integer not null default 0 check (quantity >= 0),
  condition text not null default '',
  language text not null default '',
  price numeric,
  price_cents integer,
  currency text not null default '',
  properties jsonb not null default '{}'::jsonb,
  raw_metadata jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  imported_at timestamptz,
  last_snapshot_updated_at timestamptz,
  removed_day date not null,
  archived_at timestamptz not null default now(),
  archive_reason text not null default 'missing_from_cardtrader_snapshot',
  archive_metadata jsonb not null default '{}'::jsonb
);

alter table public.cardtrader_user_listing_removed_history
  add column if not exists external_product_id text not null default '';

alter table public.cardtrader_user_listing_removed_history
  add column if not exists seller_account_id text not null default '';

alter table public.cardtrader_user_listing_removed_history
  add column if not exists seller_account_name text not null default '';

alter table public.cardtrader_user_listing_removed_history
  add column if not exists cardtrader_blueprint_id bigint;

alter table public.cardtrader_user_listing_removed_history
  add column if not exists pokoin_card_id text not null default '';

create unique index if not exists cardtrader_user_listing_removed_once_idx
  on public.cardtrader_user_listing_removed_history (
    provider,
    seller_uid,
    external_listing_id,
    removed_day
  );

create index if not exists cardtrader_user_listing_removed_blueprint_day_idx
  on public.cardtrader_user_listing_removed_history (
    coalesce(blueprint_id, cardtrader_blueprint_id),
    removed_day desc
  );

create index if not exists cardtrader_user_listing_removed_seller_day_idx
  on public.cardtrader_user_listing_removed_history (seller_uid, removed_day desc);

create or replace function public.marketplace_condition_rank(value text)
returns integer
language sql
immutable
as $$
  select case upper(coalesce(value, ''))
    when 'MT' then 1
    when 'NM' then 2
    when 'EX' then 3
    when 'GD' then 4
    when 'SP' then 5
    when 'LP' then 5
    when 'MP' then 6
    when 'PL' then 7
    when 'POOR' then 8
    else 100
  end;
$$;

create or replace function public.marketplace_price_pkn_from_cardtrader(
  amount numeric,
  amount_cents integer,
  currency text
)
returns numeric
language plpgsql
stable
as $$
declare
  fiat_amount numeric;
  reference_price numeric;
begin
  fiat_amount := coalesce(amount, amount_cents::numeric / 100);
  if fiat_amount is null or fiat_amount <= 0 then
    return null;
  end if;

  reference_price := nullif(current_setting('app.pkn_usdt_price', true), '')::numeric;
  if reference_price is null or reference_price <= 0 then
    reference_price := 0.005;
  end if;

  if upper(coalesce(currency, 'EUR')) in ('PKN', 'POKOIN') then
    return fiat_amount;
  end if;

  return fiat_amount / reference_price;
exception
  when invalid_text_representation then
    return fiat_amount / 0.005;
end;
$$;

create or replace function public.refresh_marketplace_blueprint_price_table(target_card_id text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  if target_card_id is null or trim(target_card_id) = '' then
    delete from public.marketplace_blueprint_price_table;
  else
    delete from public.marketplace_blueprint_price_table
    where blueprint_id = target_card_id::bigint;
  end if;

  insert into public.marketplace_blueprint_price_table (
    blueprint_id,
    condition,
    language,
    reverse,
    first_edition,
    foil_state,
    variant_state,
    sealed,
    signed,
    graded,
    grading_company,
    grade,
    active_listing_count,
    listed_quantity,
    lowest_ask_pkn,
    highest_ask_pkn,
    average_ask_pkn,
    median_ask_pkn,
    observation_count,
    last_observed_price_pkn,
    source_counts,
    refreshed_at
  )
  select
    source.blueprint_id,
    source.condition,
    source.language,
    source.reverse,
    source.first_edition,
    source.foil_state,
    source.variant_state,
    source.sealed,
    source.signed,
    source.graded,
    source.grading_company,
    source.grade,
    count(*) filter (where source.is_current_listing)::integer,
    coalesce(sum(source.quantity) filter (where source.is_current_listing), 0)::integer,
    min(source.price_pkn) filter (where source.is_current_listing),
    max(source.price_pkn) filter (where source.is_current_listing),
    avg(source.price_pkn) filter (where source.is_current_listing),
    percentile_cont(0.5) within group (order by source.price_pkn)
      filter (where source.is_current_listing),
    count(*)::integer,
    (array_agg(source.price_pkn order by source.observed_at desc)
      filter (where source.price_pkn is not null))[1],
    jsonb_object_agg(source.source, source.source_count) filter (where source.source_count is not null),
    now()
  from (
    select
      listing.card_id::bigint as blueprint_id,
      listing.condition,
      listing.language,
      listing.reverse,
      listing.first_edition,
      listing.foil_state,
      listing.variant_state,
      listing.sealed,
      listing.signed,
      listing.graded,
      coalesce(listing.grading_company, '') as grading_company,
      coalesce(listing.grade, '') as grade,
      listing.source,
      listing.quantity_available as quantity,
      listing.price_pkn,
      listing.updated_at as observed_at,
      true as is_current_listing,
      count(*) over (
        partition by listing.card_id::bigint, listing.condition, listing.language,
        listing.reverse, listing.first_edition, listing.foil_state,
        listing.variant_state, listing.sealed, listing.signed, listing.graded,
        coalesce(listing.grading_company, ''), coalesce(listing.grade, ''), listing.source
      )::integer as source_count
    from public.marketplace_user_listings listing
    where listing.status = 'active'
      and listing.quantity_available > 0
      and listing.price_pkn > 0
      and (target_card_id is null or trim(target_card_id) = '' or listing.card_id = target_card_id)

    union all

    select
      observation.blueprint_id,
      observation.condition,
      observation.language,
      observation.reverse,
      observation.first_edition,
      observation.foil_state,
      observation.variant_state,
      observation.sealed,
      observation.signed,
      observation.graded,
      coalesce(observation.grading_company, '') as grading_company,
      coalesce(observation.grade, '') as grade,
      observation.source,
      observation.quantity,
      observation.price_pkn,
      observation.observed_at,
      false as is_current_listing,
      count(*) over (
        partition by observation.blueprint_id, observation.condition, observation.language,
        observation.reverse, observation.first_edition, observation.foil_state,
        observation.variant_state, observation.sealed, observation.signed, observation.graded,
        coalesce(observation.grading_company, ''), coalesce(observation.grade, ''), observation.source
      )::integer as source_count
    from public.marketplace_price_observations observation
    where observation.price_pkn > 0
      and (target_card_id is null or trim(target_card_id) = '' or observation.blueprint_id = target_card_id::bigint)
  ) source
  group by
    source.blueprint_id,
    source.condition,
    source.language,
    source.reverse,
    source.first_edition,
    source.foil_state,
    source.variant_state,
    source.sealed,
    source.signed,
    source.graded,
    source.grading_company,
    source.grade;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_blueprint_price_summary(target_card_id text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  perform public.refresh_marketplace_blueprint_price_table(target_card_id);

  if target_card_id is null or trim(target_card_id) = '' then
    delete from public.marketplace_blueprint_price_summary;
  else
    delete from public.marketplace_blueprint_price_summary
    where blueprint_id = target_card_id::bigint;
  end if;

  insert into public.marketplace_blueprint_price_summary (
    blueprint_id,
    listed_quantity,
    active_listing_count,
    lowest_ask_pkn,
    median_ask_pkn,
    average_ask_pkn,
    highest_ask_pkn,
    observation_count,
    last_observed_price_pkn,
    source_counts,
    refreshed_at
  )
  select
    blueprint_id,
    sum(listed_quantity)::integer,
    sum(active_listing_count)::integer,
    min(lowest_ask_pkn),
    percentile_cont(0.5) within group (order by median_ask_pkn)
      filter (where median_ask_pkn is not null),
    avg(average_ask_pkn) filter (where average_ask_pkn is not null),
    max(highest_ask_pkn),
    sum(observation_count)::integer,
    (array_agg(last_observed_price_pkn order by refreshed_at desc)
      filter (where last_observed_price_pkn is not null))[1],
    coalesce(jsonb_object_agg(source_key, source_total) filter (where source_key is not null), '{}'::jsonb),
    now()
  from (
    select
      price_rows.*,
      source_key,
      sum((source_value)::integer) over (partition by price_rows.blueprint_id, source_key) as source_total
    from public.marketplace_blueprint_price_table price_rows
    left join lateral jsonb_each_text(price_rows.source_counts) source_entry(source_key, source_value) on true
    where target_card_id is null or trim(target_card_id) = '' or price_rows.blueprint_id = target_card_id::bigint
  ) expanded
  group by blueprint_id;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_cardtrader_blueprint_daily_analytics(target_day date default current_date - 1)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
  v_day date := coalesce(target_day, current_date - 1);
begin
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
  with current_snapshot as (
    select
      coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id,
      count(*)::integer as listing_count,
      coalesce(sum(quantity), 0)::integer as listed_quantity,
      count(distinct seller_uid)::integer as seller_count,
      min(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as min_price_pkn,
      percentile_cont(0.5) within group (
        order by public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)
      ) as median_price_pkn,
      avg(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as average_price_pkn,
      max(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as max_price_pkn
    from public.cardtrader_user_listing_snapshots
    where coalesce(blueprint_id, cardtrader_blueprint_id) is not null
      and quantity > 0
      and public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency) is not null
    group by coalesce(blueprint_id, cardtrader_blueprint_id)
  ),
  removed as (
    select
      coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id,
      count(*)::integer as sold_count,
      coalesce(sum(quantity), 0)::integer as sold_quantity
    from public.cardtrader_user_listing_removed_history
    where removed_day = v_day
      and coalesce(blueprint_id, cardtrader_blueprint_id) is not null
    group by coalesce(blueprint_id, cardtrader_blueprint_id)
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
      coalesce(current_snapshot.blueprint_id, removed.blueprint_id) as blueprint_id,
      coalesce(current_snapshot.listing_count, 0) as listing_count,
      coalesce(current_snapshot.listed_quantity, 0) as listed_quantity,
      coalesce(current_snapshot.seller_count, 0) as seller_count,
      coalesce(removed.sold_count, 0) as sold_count,
      coalesce(removed.sold_quantity, 0) as sold_quantity,
      current_snapshot.min_price_pkn,
      current_snapshot.median_price_pkn,
      current_snapshot.average_price_pkn,
      current_snapshot.max_price_pkn,
      previous_day.min_price_pkn as previous_min_price_pkn
    from current_snapshot
    full outer join removed on removed.blueprint_id = current_snapshot.blueprint_id
    left join previous_day on previous_day.blueprint_id = coalesce(current_snapshot.blueprint_id, removed.blueprint_id)
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
      'cardtrader_snapshot', combined.listing_count,
      'cardtrader_removed', combined.sold_count
    ),
    now()
  from combined
  where combined.blueprint_id is not null;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_hot_blueprints()
returns integer
language plpgsql
security definer
set search_path = public
as $$
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
      event.card_id as blueprint_id,
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
    group by event.card_id
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
      c.card_id as blueprint_id,
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
    left join event_rollup e on e.blueprint_id = c.card_id
    left join cardtrader_rollup ct on ct.blueprint_id = c.card_id
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
$$;

create or replace function public.refresh_cardtrader_user_listing_snapshots(
  p_provider text,
  p_seller_uid text,
  p_rows jsonb,
  p_removed_day date default current_date - 1,
  p_archive_missing boolean default true,
  p_imported_at timestamptz default now()
)
returns table (
  archived_count integer,
  deleted_count integer,
  upserted_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_seller_uid text := coalesce(nullif(trim(p_seller_uid), ''), '');
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_removed_day date := coalesce(p_removed_day, current_date - 1);
begin
  if v_seller_uid = '' then
    raise exception 'seller uid is required';
  end if;

  if jsonb_typeof(v_rows) <> 'array' then
    raise exception 'rows must be a JSONB array';
  end if;

  create temp table if not exists pg_temp.cardtrader_user_listing_refresh_rows (
    provider text not null,
    seller_uid text not null,
    seller_account_id text not null,
    seller_account_name text not null,
    external_listing_id text not null,
    external_product_id text not null,
    blueprint_id bigint,
    cardtrader_blueprint_id bigint,
    pokoin_card_id text not null,
    quantity integer not null,
    condition text not null,
    language text not null,
    price numeric,
    price_cents integer,
    currency text not null,
    properties jsonb not null,
    raw_metadata jsonb not null
  ) on commit drop;

  truncate table pg_temp.cardtrader_user_listing_refresh_rows;

  insert into pg_temp.cardtrader_user_listing_refresh_rows (
    provider,
    seller_uid,
    seller_account_id,
    seller_account_name,
    external_listing_id,
    external_product_id,
    blueprint_id,
    cardtrader_blueprint_id,
    pokoin_card_id,
    quantity,
    condition,
    language,
    price,
    price_cents,
    currency,
    properties,
    raw_metadata
  )
  select distinct on (v_provider, v_seller_uid, normalized.external_listing_id)
    v_provider,
    v_seller_uid,
    normalized.seller_account_id,
    normalized.seller_account_name,
    normalized.external_listing_id,
    normalized.external_product_id,
    normalized.blueprint_id,
    normalized.cardtrader_blueprint_id,
    normalized.pokoin_card_id,
    normalized.quantity,
    normalized.condition,
    normalized.language,
    normalized.price,
    normalized.price_cents,
    normalized.currency,
    normalized.properties,
    normalized.raw_metadata
  from (
    select
      left(coalesce(row_data->>'sellerAccountId', row_data->>'seller_account_id', ''), 160) as seller_account_id,
      left(coalesce(row_data->>'sellerAccountName', row_data->>'seller_account_name', ''), 240) as seller_account_name,
      left(coalesce(row_data->>'externalListingId', row_data->>'external_listing_id', row_data->>'id', ''), 160) as external_listing_id,
      left(coalesce(row_data->>'externalProductId', row_data->>'external_product_id', row_data->>'productId', row_data->>'product_id', ''), 160) as external_product_id,
      nullif(coalesce(row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as blueprint_id,
      nullif(coalesce(row_data->>'cardtraderBlueprintId', row_data->>'cardtrader_blueprint_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as cardtrader_blueprint_id,
      left(coalesce(row_data->>'pokoinCardId', row_data->>'pokoin_card_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), 80) as pokoin_card_id,
      greatest(coalesce(nullif(coalesce(row_data->>'quantity', row_data->>'qty', ''), '')::integer, 0), 0) as quantity,
      left(coalesce(row_data->>'condition', row_data->>'state', ''), 80) as condition,
      left(coalesce(row_data->>'language', row_data->>'lang', ''), 40) as language,
      nullif(coalesce(row_data->>'price', row_data->>'priceAmount', row_data->>'price_amount', ''), '')::numeric as price,
      nullif(coalesce(row_data->>'priceCents', row_data->>'price_cents', ''), '')::integer as price_cents,
      left(coalesce(row_data->>'currency', ''), 12) as currency,
      coalesce(row_data->'properties', '{}'::jsonb) as properties,
      coalesce(row_data->'rawMetadata', row_data->'raw_metadata', row_data, '{}'::jsonb) as raw_metadata
    from jsonb_array_elements(v_rows) as payload(row_data)
  ) normalized
  where normalized.external_listing_id <> ''
  order by v_provider, v_seller_uid, normalized.external_listing_id;

  if p_archive_missing then
    insert into public.cardtrader_user_listing_removed_history (
      provider,
      seller_uid,
      seller_account_id,
      seller_account_name,
      external_listing_id,
      external_product_id,
      blueprint_id,
      cardtrader_blueprint_id,
      pokoin_card_id,
      quantity,
      condition,
      language,
      price,
      price_cents,
      currency,
      properties,
      raw_metadata,
      first_seen_at,
      last_seen_at,
      imported_at,
      last_snapshot_updated_at,
      removed_day,
      archive_reason,
      archive_metadata
    )
    select
      existing.provider,
      existing.seller_uid,
      existing.seller_account_id,
      existing.seller_account_name,
      existing.external_listing_id,
      existing.external_product_id,
      existing.blueprint_id,
      existing.cardtrader_blueprint_id,
      existing.pokoin_card_id,
      existing.quantity,
      existing.condition,
      existing.language,
      existing.price,
      existing.price_cents,
      existing.currency,
      existing.properties,
      existing.raw_metadata,
      existing.first_seen_at,
      existing.last_seen_at,
      existing.imported_at,
      existing.updated_at,
      v_removed_day,
      'missing_from_cardtrader_snapshot',
      jsonb_build_object('refreshImportedAt', p_imported_at)
    from public.cardtrader_user_listing_snapshots existing
    left join pg_temp.cardtrader_user_listing_refresh_rows incoming
      on incoming.provider = existing.provider
      and incoming.seller_uid = existing.seller_uid
      and incoming.external_listing_id = existing.external_listing_id
    where existing.provider = v_provider
      and existing.seller_uid = v_seller_uid
      and incoming.external_listing_id is null
    on conflict (provider, seller_uid, external_listing_id, removed_day) do nothing;

    get diagnostics archived_count = row_count;

    delete from public.cardtrader_user_listing_snapshots existing
    where existing.provider = v_provider
      and existing.seller_uid = v_seller_uid
      and not exists (
        select 1
        from pg_temp.cardtrader_user_listing_refresh_rows incoming
        where incoming.provider = existing.provider
          and incoming.seller_uid = existing.seller_uid
          and incoming.external_listing_id = existing.external_listing_id
      );

    get diagnostics deleted_count = row_count;
  else
    archived_count := 0;
    deleted_count := 0;
  end if;

  insert into public.cardtrader_user_listing_snapshots (
    provider,
    seller_uid,
    seller_account_id,
    seller_account_name,
    external_listing_id,
    external_product_id,
    blueprint_id,
    cardtrader_blueprint_id,
    pokoin_card_id,
    quantity,
    condition,
    language,
    price,
    price_cents,
    currency,
    properties,
    raw_metadata,
    first_seen_at,
    last_seen_at,
    imported_at,
    updated_at
  )
  select
    incoming.provider,
    incoming.seller_uid,
    incoming.seller_account_id,
    incoming.seller_account_name,
    incoming.external_listing_id,
    incoming.external_product_id,
    incoming.blueprint_id,
    incoming.cardtrader_blueprint_id,
    incoming.pokoin_card_id,
    incoming.quantity,
    incoming.condition,
    incoming.language,
    incoming.price,
    incoming.price_cents,
    incoming.currency,
    incoming.properties,
    incoming.raw_metadata,
    p_imported_at,
    p_imported_at,
    p_imported_at,
    p_imported_at
  from pg_temp.cardtrader_user_listing_refresh_rows incoming
  on conflict (provider, seller_uid, external_listing_id) do update set
    seller_account_id = excluded.seller_account_id,
    seller_account_name = excluded.seller_account_name,
    external_product_id = excluded.external_product_id,
    blueprint_id = excluded.blueprint_id,
    cardtrader_blueprint_id = excluded.cardtrader_blueprint_id,
    pokoin_card_id = excluded.pokoin_card_id,
    quantity = excluded.quantity,
    condition = excluded.condition,
    language = excluded.language,
    price = excluded.price,
    price_cents = excluded.price_cents,
    currency = excluded.currency,
    properties = excluded.properties,
    raw_metadata = excluded.raw_metadata,
    last_seen_at = excluded.last_seen_at,
    imported_at = excluded.imported_at,
    updated_at = excluded.updated_at;

  get diagnostics upserted_count = row_count;

  insert into public.marketplace_price_observations (
    blueprint_id,
    source,
    source_item_id,
    observed_at,
    currency,
    price,
    price_pkn,
    quantity,
    condition,
    language,
    reverse,
    first_edition,
    foil_state,
    variant_state,
    sealed,
    signed,
    graded,
    grading_company,
    grade,
    metadata,
    created_at
  )
  select
    coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id),
    'cardtrader_snapshot',
    snapshot.provider || ':' || snapshot.seller_uid || ':' || snapshot.external_listing_id || ':' || p_imported_at::date::text,
    p_imported_at,
    coalesce(nullif(snapshot.currency, ''), 'EUR'),
    coalesce(snapshot.price, snapshot.price_cents::numeric / 100),
    public.marketplace_price_pkn_from_cardtrader(snapshot.price, snapshot.price_cents, snapshot.currency),
    snapshot.quantity,
    coalesce(nullif(snapshot.condition, ''), 'NM'),
    coalesce(nullif(snapshot.language, ''), 'EN'),
    false,
    false,
    case when lower(coalesce(snapshot.properties->>'foil_state', snapshot.properties->>'foilState', '')) = 'reverse' then 'reverse' else 'standard' end,
    coalesce(snapshot.properties->>'variant_state', snapshot.properties->>'variantState', ''),
    false,
    false,
    false,
    '',
    '',
    jsonb_build_object(
      'provider', snapshot.provider,
      'sellerUid', snapshot.seller_uid,
      'sellerAccountId', snapshot.seller_account_id,
      'sellerAccountName', snapshot.seller_account_name,
      'externalListingId', snapshot.external_listing_id,
      'externalProductId', snapshot.external_product_id,
      'observationKind', 'current_listing_snapshot',
      'observedDay', p_imported_at::date
    ) || jsonb_build_object('raw', snapshot.raw_metadata),
    p_imported_at
  from public.cardtrader_user_listing_snapshots snapshot
  where snapshot.provider = v_provider
    and snapshot.seller_uid = v_seller_uid
    and coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id) is not null
    and snapshot.quantity > 0
    and public.marketplace_price_pkn_from_cardtrader(snapshot.price, snapshot.price_cents, snapshot.currency) is not null
    and not exists (
      select 1
      from public.marketplace_price_observations existing
      where existing.source = 'cardtrader_snapshot'
        and existing.source_item_id = snapshot.provider || ':' || snapshot.seller_uid || ':' || snapshot.external_listing_id || ':' || p_imported_at::date::text
    );

  insert into public.marketplace_price_observations (
    blueprint_id,
    source,
    source_item_id,
    observed_at,
    currency,
    price,
    price_pkn,
    quantity,
    condition,
    language,
    reverse,
    first_edition,
    foil_state,
    variant_state,
    sealed,
    signed,
    graded,
    grading_company,
    grade,
    metadata,
    created_at
  )
  select
    coalesce(history.blueprint_id, history.cardtrader_blueprint_id),
    'cardtrader_removed_sale',
    history.provider || ':' || history.seller_uid || ':' || history.external_listing_id || ':' || history.removed_day::text,
    history.removed_day::timestamptz,
    coalesce(nullif(history.currency, ''), 'EUR'),
    coalesce(history.price, history.price_cents::numeric / 100),
    public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency),
    history.quantity,
    coalesce(nullif(history.condition, ''), 'NM'),
    coalesce(nullif(history.language, ''), 'EN'),
    false,
    false,
    case when lower(coalesce(history.properties->>'foil_state', history.properties->>'foilState', '')) = 'reverse' then 'reverse' else 'standard' end,
    coalesce(history.properties->>'variant_state', history.properties->>'variantState', ''),
    false,
    false,
    false,
    '',
    '',
    jsonb_build_object(
      'provider', history.provider,
      'sellerUid', history.seller_uid,
      'sellerAccountId', history.seller_account_id,
      'sellerAccountName', history.seller_account_name,
      'externalListingId', history.external_listing_id,
      'externalProductId', history.external_product_id,
      'observationKind', 'removed_or_sold_listing',
      'observedDay', history.removed_day,
      'removedDay', history.removed_day
    ) || jsonb_build_object('raw', history.raw_metadata),
    now()
  from public.cardtrader_user_listing_removed_history history
  where history.provider = v_provider
    and history.seller_uid = v_seller_uid
    and history.removed_day = v_removed_day
    and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
    and public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency) is not null
    and not exists (
      select 1
      from public.marketplace_price_observations existing
      where existing.source = 'cardtrader_removed_sale'
        and existing.source_item_id = history.provider || ':' || history.seller_uid || ':' || history.external_listing_id || ':' || history.removed_day::text
    );

  perform public.refresh_cardtrader_blueprint_daily_analytics(v_removed_day);

  perform public.refresh_marketplace_blueprint_price_summary(blueprint_id::text)
  from (
    select distinct coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id
    from public.cardtrader_user_listing_snapshots
    where provider = v_provider
      and seller_uid = v_seller_uid
      and coalesce(blueprint_id, cardtrader_blueprint_id) is not null
    union
    select distinct coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id
    from public.cardtrader_user_listing_removed_history
    where provider = v_provider
      and seller_uid = v_seller_uid
      and removed_day = v_removed_day
      and coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  ) touched_blueprints;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$$;
