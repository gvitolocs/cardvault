create table if not exists public.cardtrader_market_listing_snapshots (
  provider text not null default 'cardtrader',
  external_listing_id text not null,
  external_product_id text not null default '',
  blueprint_id bigint,
  cardtrader_blueprint_id bigint,
  pokoin_card_id text not null default '',
  seller_account_id text not null default '',
  seller_account_name text not null default '',
  seller_country text not null default '',
  seller_type text not null default '',
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
  primary key (provider, external_listing_id)
);

alter table public.cardtrader_market_listing_snapshots
  add column if not exists external_product_id text not null default '';

alter table public.cardtrader_market_listing_snapshots
  add column if not exists seller_account_id text not null default '';

alter table public.cardtrader_market_listing_snapshots
  add column if not exists seller_account_name text not null default '';

alter table public.cardtrader_market_listing_snapshots
  add column if not exists seller_country text not null default '';

alter table public.cardtrader_market_listing_snapshots
  add column if not exists seller_type text not null default '';

alter table public.cardtrader_market_listing_snapshots
  add column if not exists cardtrader_blueprint_id bigint;

alter table public.cardtrader_market_listing_snapshots
  add column if not exists pokoin_card_id text not null default '';

create index if not exists cardtrader_market_listing_snapshots_blueprint_idx
  on public.cardtrader_market_listing_snapshots (
    coalesce(blueprint_id, cardtrader_blueprint_id),
    last_seen_at desc
  );

create index if not exists cardtrader_market_listing_snapshots_product_idx
  on public.cardtrader_market_listing_snapshots (provider, external_product_id)
  where external_product_id <> '';

create index if not exists cardtrader_market_listing_snapshots_seller_idx
  on public.cardtrader_market_listing_snapshots (seller_account_id, last_seen_at desc)
  where seller_account_id <> '';

create table if not exists public.cardtrader_market_listing_removed_history (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'cardtrader',
  external_listing_id text not null,
  external_product_id text not null default '',
  blueprint_id bigint,
  cardtrader_blueprint_id bigint,
  pokoin_card_id text not null default '',
  seller_account_id text not null default '',
  seller_account_name text not null default '',
  seller_country text not null default '',
  seller_type text not null default '',
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
  archive_reason text not null default 'missing_from_cardtrader_market_snapshot',
  archive_metadata jsonb not null default '{}'::jsonb
);

alter table public.cardtrader_market_listing_removed_history
  add column if not exists external_product_id text not null default '';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists seller_account_id text not null default '';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists seller_account_name text not null default '';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists seller_country text not null default '';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists seller_type text not null default '';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists cardtrader_blueprint_id bigint;

alter table public.cardtrader_market_listing_removed_history
  add column if not exists pokoin_card_id text not null default '';

create unique index if not exists cardtrader_market_listing_removed_once_idx
  on public.cardtrader_market_listing_removed_history (
    provider,
    external_listing_id,
    removed_day
  );

create index if not exists cardtrader_market_listing_removed_blueprint_day_idx
  on public.cardtrader_market_listing_removed_history (
    coalesce(blueprint_id, cardtrader_blueprint_id),
    removed_day desc
  );

create index if not exists cardtrader_market_listing_removed_seller_day_idx
  on public.cardtrader_market_listing_removed_history (seller_account_id, removed_day desc)
  where seller_account_id <> '';

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
      ) + 200 as price_pkn,
      snapshot.quantity,
      'zero'::text as shipping_mode,
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
    left(coalesce(nullif(ranked.pokoin_card_id, ''), ranked.blueprint_id::text), 80),
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
      count(distinct nullif(seller_account_id, ''))::integer as seller_count,
      min(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as min_price_pkn,
      percentile_cont(0.5) within group (
        order by public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)
      ) as median_price_pkn,
      avg(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as average_price_pkn,
      max(public.marketplace_price_pkn_from_cardtrader(price, price_cents, currency)) as max_price_pkn
    from public.cardtrader_market_listing_snapshots
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
    from public.cardtrader_market_listing_removed_history
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
      'cardtrader_market_snapshot', combined.listing_count,
      'cardtrader_market_removed', combined.sold_count
    ),
    now()
  from combined
  where combined.blueprint_id is not null;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

drop function if exists public.refresh_cardtrader_market_listing_snapshots(
  text,
  jsonb,
  jsonb,
  date,
  boolean,
  timestamptz
);

create or replace function public.refresh_cardtrader_market_listing_snapshots(
  p_provider text,
  p_rows jsonb,
  p_scope_blueprint_ids jsonb default '[]'::jsonb,
  p_removed_day date default current_date - 1,
  p_archive_missing boolean default true,
  p_imported_at timestamptz default now()
)
returns table (
  archived_count integer,
  deleted_count integer,
  upserted_count integer,
  cache_refreshed_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_scope_blueprint_ids jsonb := coalesce(p_scope_blueprint_ids, '[]'::jsonb);
  v_removed_day date := coalesce(p_removed_day, current_date - 1);
  v_cache_scope_blueprint_ids jsonb := '[]'::jsonb;
  v_cache_refreshed_count integer := 0;
begin
  if jsonb_typeof(v_rows) <> 'array' then
    raise exception 'rows must be a JSONB array';
  end if;

  if jsonb_typeof(v_scope_blueprint_ids) <> 'array' then
    raise exception 'scope blueprint ids must be a JSONB array';
  end if;

  create temp table if not exists pg_temp.cardtrader_market_listing_refresh_rows (
    provider text not null,
    external_listing_id text not null,
    external_product_id text not null,
    blueprint_id bigint,
    cardtrader_blueprint_id bigint,
    pokoin_card_id text not null,
    seller_account_id text not null,
    seller_account_name text not null,
    seller_country text not null,
    seller_type text not null,
    quantity integer not null,
    condition text not null,
    language text not null,
    price numeric,
    price_cents integer,
    currency text not null,
    properties jsonb not null,
    raw_metadata jsonb not null
  ) on commit drop;

  create temp table if not exists pg_temp.cardtrader_market_listing_refresh_scope (
    blueprint_id bigint primary key
  ) on commit drop;

  truncate table pg_temp.cardtrader_market_listing_refresh_rows;
  truncate table pg_temp.cardtrader_market_listing_refresh_scope;

  insert into pg_temp.cardtrader_market_listing_refresh_rows (
    provider,
    external_listing_id,
    external_product_id,
    blueprint_id,
    cardtrader_blueprint_id,
    pokoin_card_id,
    seller_account_id,
    seller_account_name,
    seller_country,
    seller_type,
    quantity,
    condition,
    language,
    price,
    price_cents,
    currency,
    properties,
    raw_metadata
  )
  select distinct on (v_provider, normalized.external_listing_id)
    v_provider,
    normalized.external_listing_id,
    normalized.external_product_id,
    normalized.blueprint_id,
    normalized.cardtrader_blueprint_id,
    normalized.pokoin_card_id,
    normalized.seller_account_id,
    normalized.seller_account_name,
    normalized.seller_country,
    normalized.seller_type,
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
      left(coalesce(row_data->>'externalListingId', row_data->>'external_listing_id', row_data->>'id', ''), 160) as external_listing_id,
      left(coalesce(row_data->>'externalProductId', row_data->>'external_product_id', row_data->>'productId', row_data->>'product_id', ''), 160) as external_product_id,
      nullif(coalesce(row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as blueprint_id,
      nullif(coalesce(row_data->>'cardtraderBlueprintId', row_data->>'cardtrader_blueprint_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as cardtrader_blueprint_id,
      left(coalesce(row_data->>'pokoinCardId', row_data->>'pokoin_card_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), 80) as pokoin_card_id,
      left(coalesce(row_data->>'sellerAccountId', row_data->>'seller_account_id', ''), 160) as seller_account_id,
      left(coalesce(row_data->>'sellerAccountName', row_data->>'seller_account_name', ''), 240) as seller_account_name,
      left(coalesce(row_data->>'sellerCountry', row_data->>'seller_country', ''), 40) as seller_country,
      left(coalesce(row_data->>'sellerType', row_data->>'seller_type', ''), 80) as seller_type,
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
  order by v_provider, normalized.external_listing_id;

  insert into pg_temp.cardtrader_market_listing_refresh_scope (blueprint_id)
  select distinct value::bigint
  from jsonb_array_elements_text(v_scope_blueprint_ids) as scope(value)
  where value ~ '^[0-9]+$'
  on conflict do nothing;

  insert into pg_temp.cardtrader_market_listing_refresh_scope (blueprint_id)
  select distinct coalesce(blueprint_id, cardtrader_blueprint_id)
  from pg_temp.cardtrader_market_listing_refresh_rows
  where coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  on conflict do nothing;

  if p_archive_missing and exists (select 1 from pg_temp.cardtrader_market_listing_refresh_scope) then
    insert into public.cardtrader_market_listing_removed_history (
      provider,
      external_listing_id,
      external_product_id,
      blueprint_id,
      cardtrader_blueprint_id,
      pokoin_card_id,
      seller_account_id,
      seller_account_name,
      seller_country,
      seller_type,
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
      existing.external_listing_id,
      existing.external_product_id,
      existing.blueprint_id,
      existing.cardtrader_blueprint_id,
      existing.pokoin_card_id,
      existing.seller_account_id,
      existing.seller_account_name,
      existing.seller_country,
      existing.seller_type,
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
      'missing_from_cardtrader_market_snapshot',
      jsonb_build_object('refreshImportedAt', p_imported_at)
    from public.cardtrader_market_listing_snapshots existing
    join pg_temp.cardtrader_market_listing_refresh_scope scope
      on scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    left join pg_temp.cardtrader_market_listing_refresh_rows incoming
      on incoming.provider = existing.provider
      and incoming.external_listing_id = existing.external_listing_id
    where existing.provider = v_provider
      and incoming.external_listing_id is null
    on conflict (provider, external_listing_id, removed_day) do nothing;

    get diagnostics archived_count = row_count;

    delete from public.cardtrader_market_listing_snapshots existing
    using pg_temp.cardtrader_market_listing_refresh_scope scope
    where existing.provider = v_provider
      and scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
      and not exists (
        select 1
        from pg_temp.cardtrader_market_listing_refresh_rows incoming
        where incoming.provider = existing.provider
          and incoming.external_listing_id = existing.external_listing_id
      );

    get diagnostics deleted_count = row_count;
  else
    archived_count := 0;
    deleted_count := 0;
  end if;

  insert into public.cardtrader_market_listing_snapshots (
    provider,
    external_listing_id,
    external_product_id,
    blueprint_id,
    cardtrader_blueprint_id,
    pokoin_card_id,
    seller_account_id,
    seller_account_name,
    seller_country,
    seller_type,
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
    incoming.external_listing_id,
    incoming.external_product_id,
    incoming.blueprint_id,
    incoming.cardtrader_blueprint_id,
    incoming.pokoin_card_id,
    incoming.seller_account_id,
    incoming.seller_account_name,
    incoming.seller_country,
    incoming.seller_type,
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
  from pg_temp.cardtrader_market_listing_refresh_rows incoming
  on conflict (provider, external_listing_id) do update set
    external_product_id = excluded.external_product_id,
    blueprint_id = excluded.blueprint_id,
    cardtrader_blueprint_id = excluded.cardtrader_blueprint_id,
    pokoin_card_id = excluded.pokoin_card_id,
    seller_account_id = excluded.seller_account_id,
    seller_account_name = excluded.seller_account_name,
    seller_country = excluded.seller_country,
    seller_type = excluded.seller_type,
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

  select coalesce(jsonb_agg(scope.blueprint_id), '[]'::jsonb)
  from pg_temp.cardtrader_market_listing_refresh_scope scope
  into v_cache_scope_blueprint_ids;

  if jsonb_array_length(v_cache_scope_blueprint_ids) > 0 then
    select public.refresh_cardtrader_blueprint_listing_cache(
      v_provider,
      v_cache_scope_blueprint_ids,
      p_imported_at
    )
    into v_cache_refreshed_count;
  end if;

  cache_refreshed_count := coalesce(v_cache_refreshed_count, 0);

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
    snapshot.provider || ':' || snapshot.external_listing_id || ':' || p_imported_at::date::text,
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
    lower(coalesce(snapshot.raw_metadata->>'graded', '')) in ('true', '1', 'yes'),
    '',
    '',
    jsonb_build_object(
      'provider', snapshot.provider,
      'sellerAccountId', snapshot.seller_account_id,
      'sellerAccountName', snapshot.seller_account_name,
      'sellerCountry', snapshot.seller_country,
      'sellerType', snapshot.seller_type,
      'externalListingId', snapshot.external_listing_id,
      'externalProductId', snapshot.external_product_id,
      'observationKind', 'global_market_listing_snapshot',
      'observedDay', p_imported_at::date
    ) || jsonb_build_object('raw', snapshot.raw_metadata),
    p_imported_at
  from public.cardtrader_market_listing_snapshots snapshot
  join pg_temp.cardtrader_market_listing_refresh_scope scope
    on scope.blueprint_id = coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id)
  where snapshot.provider = v_provider
    and coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id) is not null
    and snapshot.quantity > 0
    and public.marketplace_price_pkn_from_cardtrader(snapshot.price, snapshot.price_cents, snapshot.currency) is not null
    and not exists (
      select 1
      from public.marketplace_price_observations existing
      where existing.source = 'cardtrader_snapshot'
        and existing.source_item_id = snapshot.provider || ':' || snapshot.external_listing_id || ':' || p_imported_at::date::text
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
    history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text,
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
    lower(coalesce(history.raw_metadata->>'graded', '')) in ('true', '1', 'yes'),
    '',
    '',
    jsonb_build_object(
      'provider', history.provider,
      'sellerAccountId', history.seller_account_id,
      'sellerAccountName', history.seller_account_name,
      'sellerCountry', history.seller_country,
      'sellerType', history.seller_type,
      'externalListingId', history.external_listing_id,
      'externalProductId', history.external_product_id,
      'observationKind', 'global_market_listing_removed_or_sold',
      'observedDay', history.removed_day,
      'removedDay', history.removed_day
    ) || jsonb_build_object('raw', history.raw_metadata),
    now()
  from public.cardtrader_market_listing_removed_history history
  where history.provider = v_provider
    and history.removed_day = v_removed_day
    and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
    and public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency) is not null
    and not exists (
      select 1
      from public.marketplace_price_observations existing
      where existing.source = 'cardtrader_removed_sale'
        and existing.source_item_id = history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text
    );

  perform public.refresh_cardtrader_blueprint_daily_analytics(v_removed_day);

  perform public.refresh_marketplace_blueprint_price_summary(blueprint_id::text)
  from (
    select distinct coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id
    from public.cardtrader_market_listing_snapshots
    where provider = v_provider
      and coalesce(blueprint_id, cardtrader_blueprint_id) is not null
      and coalesce(blueprint_id, cardtrader_blueprint_id) in (
        select scope.blueprint_id from pg_temp.cardtrader_market_listing_refresh_scope scope
      )
    union
    select distinct coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id
    from public.cardtrader_market_listing_removed_history
    where provider = v_provider
      and removed_day = v_removed_day
      and coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  ) touched_blueprints;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$$;
