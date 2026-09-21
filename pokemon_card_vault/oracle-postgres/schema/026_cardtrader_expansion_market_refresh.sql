-- Daily CardTrader market import is expansion-scoped (GET /marketplace/products?expansion_id=).
-- CardTrader returns the cheapest 25 listings per blueprint. Sold comps are inferred from:
--   inferred_sale / missing_from_cardtrader_market_snapshot — listing left the cheap-25 window
--   quantity_decreased — same listing, lower quantity
--   dropped_from_cheapest_25 — still for sale, just no longer in the cheap 25 (not a sale)
-- Ask snapshots stay in cardtrader_market_listing_snapshots; do not duplicate them daily
-- into marketplace_price_observations. Homepage cache is derived from snapshots.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

create index if not exists cardtrader_market_listing_removed_reason_day_idx
  on public.cardtrader_market_listing_removed_history (archive_reason, removed_day desc);

create or replace function public.cardtrader_market_archive_reason(
  incoming_listing_count integer,
  incoming_ceiling_price numeric,
  existing_price numeric
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(incoming_listing_count, 0) < 25 then 'inferred_sale'
    when existing_price is null then 'inferred_sale'
    when incoming_ceiling_price is null then 'inferred_sale'
    when existing_price <= incoming_ceiling_price then 'inferred_sale'
    else 'dropped_from_cheapest_25'
  end;
$$;

create or replace function public.cardtrader_default_language_for_nationality(nationality text)
returns text
language sql
immutable
parallel safe
as $$
  select case lower(btrim(coalesce(nationality, '')))
    when 'japanese' then 'JP'
    when 'korean' then 'KO'
    when 'chinese' then 'ZH'
    when 'indonesian' then 'ID'
    when 'idth' then 'ID'
    when 'thai' then 'TH'
    when 'french' then 'FR'
    when 'german' then 'DE'
    else 'EN'
  end;
$$;

create or replace function public.cardtrader_listing_language(
  stored_language text,
  properties jsonb default '{}'::jsonb,
  nationality text default ''
)
returns text
language sql
immutable
parallel safe
as $$
  select coalesce(
    public.cardtrader_sold_language(nullif(btrim(coalesce(properties->>'pokemon_language', '')), '')),
    case
      when public.cardtrader_sold_language(stored_language) is not null
        and public.cardtrader_sold_language(stored_language) is distinct from 'EN'
        then public.cardtrader_sold_language(stored_language)
      else public.cardtrader_default_language_for_nationality(nationality)
    end
  );
$$;

create or replace function public.cardtrader_listing_language_for_blueprint(
  stored_language text,
  properties jsonb,
  p_blueprint_id bigint
)
returns text
language sql
stable
as $$
  select public.cardtrader_listing_language(
    stored_language,
    coalesce(properties, '{}'::jsonb),
    (
      select e.nationality
      from public.pokoin_pokemon_blueprints b
      join public.pokoin_pokemon_expansions e on e.expansion_id = b.expansion_id
      where b.id = p_blueprint_id
      limit 1
    )
  );
$$;

create or replace function public.cardtrader_market_is_sale_reason(reason text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(reason, '')) in (
    'inferred_sale',
    'quantity_decreased',
    'missing_from_cardtrader_market_snapshot'
  );
$$;

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
      and public.cardtrader_market_is_sale_reason(archive_reason)
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

drop function if exists public.refresh_cardtrader_market_listing_snapshots(
  text,
  jsonb,
  jsonb,
  date,
  boolean,
  timestamptz,
  boolean,
  boolean
);

create or replace function public.refresh_cardtrader_market_listing_snapshots(
  p_provider text,
  p_rows jsonb,
  p_scope_blueprint_ids jsonb default '[]'::jsonb,
  p_removed_day date default current_date - 1,
  p_archive_missing boolean default true,
  p_imported_at timestamptz default now(),
  p_finalize boolean default true,
  p_record_ask_observations boolean default false
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
set statement_timeout = 0
as $$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_scope_blueprint_ids jsonb := coalesce(p_scope_blueprint_ids, '[]'::jsonb);
  v_removed_day date := coalesce(p_removed_day, current_date - 1);
  v_cache_scope_blueprint_ids jsonb := '[]'::jsonb;
  v_cache_refreshed_count integer := 0;
  v_quantity_decreased_count integer := 0;
begin
  perform set_config('statement_timeout', '0', true);
  perform set_config('lock_timeout', '0', true);

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

  create temp table if not exists pg_temp.cardtrader_market_listing_incoming_stats (
    blueprint_id bigint primary key,
    listing_count integer not null,
    ceiling_price numeric
  ) on commit drop;

  truncate table pg_temp.cardtrader_market_listing_refresh_rows;
  truncate table pg_temp.cardtrader_market_listing_refresh_scope;
  truncate table pg_temp.cardtrader_market_listing_incoming_stats;

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
      left(coalesce(
        nullif(row_data->>'pokoinCardId', ''),
        nullif(row_data->>'pokoin_card_id', ''),
        (nullif(coalesce(row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint * 2)::text,
        ''
      ), 80) as pokoin_card_id,
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

  insert into pg_temp.cardtrader_market_listing_incoming_stats (
    blueprint_id,
    listing_count,
    ceiling_price
  )
  select
    coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id,
    count(*)::integer,
    max(coalesce(price, price_cents::numeric / 100))
  from pg_temp.cardtrader_market_listing_refresh_rows
  where coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  group by coalesce(blueprint_id, cardtrader_blueprint_id)
  on conflict do nothing;

  if exists (select 1 from pg_temp.cardtrader_market_listing_refresh_scope) then
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
      greatest(existing.quantity - incoming.quantity, 0),
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
      'quantity_decreased',
      jsonb_build_object(
        'refreshImportedAt', p_imported_at,
        'previousQuantity', existing.quantity,
        'currentQuantity', incoming.quantity
      )
    from public.cardtrader_market_listing_snapshots existing
    join pg_temp.cardtrader_market_listing_refresh_rows incoming
      on incoming.provider = existing.provider
      and incoming.external_listing_id = existing.external_listing_id
    join pg_temp.cardtrader_market_listing_refresh_scope scope
      on scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    where existing.provider = v_provider
      and existing.quantity > incoming.quantity
    on conflict (provider, external_listing_id, removed_day) do nothing;

    get diagnostics v_quantity_decreased_count = row_count;
  end if;

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
      case
        when exists (
          select 1
          from pg_temp.cardtrader_market_listing_refresh_rows successor
          where successor.provider = existing.provider
            and successor.seller_account_id <> ''
            and successor.seller_account_id = existing.seller_account_id
            and coalesce(successor.blueprint_id, successor.cardtrader_blueprint_id)
                is not distinct from coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
            and successor.condition is not distinct from existing.condition
            and successor.language is not distinct from existing.language
            and successor.external_listing_id is distinct from existing.external_listing_id
            and not exists (
              select 1
              from public.cardtrader_market_listing_snapshots prev
              where prev.provider = successor.provider
                and prev.external_listing_id = successor.external_listing_id
            )
            and public.cardtrader_listing_is_reverse(successor.properties, false, '')
                is not distinct from public.cardtrader_listing_is_reverse(existing.properties, false, '')
            and public.cardtrader_listing_is_first_edition(successor.properties, false)
                is not distinct from public.cardtrader_listing_is_first_edition(existing.properties, false)
        ) then 'listing_id_rotated'
        else public.cardtrader_market_archive_reason(
          stats.listing_count,
          stats.ceiling_price,
          coalesce(existing.price, existing.price_cents::numeric / 100)
        )
      end,
      jsonb_build_object(
        'refreshImportedAt', p_imported_at,
        'incomingListingCount', coalesce(stats.listing_count, 0),
        'incomingCeilingPrice', stats.ceiling_price
      ) || case
        when exists (
          select 1
          from pg_temp.cardtrader_market_listing_refresh_rows successor
          where successor.provider = existing.provider
            and successor.seller_account_id <> ''
            and successor.seller_account_id = existing.seller_account_id
            and coalesce(successor.blueprint_id, successor.cardtrader_blueprint_id)
                is not distinct from coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
            and successor.condition is not distinct from existing.condition
            and successor.language is not distinct from existing.language
            and successor.external_listing_id is distinct from existing.external_listing_id
            and not exists (
              select 1
              from public.cardtrader_market_listing_snapshots prev
              where prev.provider = successor.provider
                and prev.external_listing_id = successor.external_listing_id
            )
            and public.cardtrader_listing_is_reverse(successor.properties, false, '')
                is not distinct from public.cardtrader_listing_is_reverse(existing.properties, false, '')
            and public.cardtrader_listing_is_first_edition(successor.properties, false)
                is not distinct from public.cardtrader_listing_is_first_edition(existing.properties, false)
        ) then jsonb_build_object('reclassifiedBecause', 'same_seller_stack_new_product_id')
        else '{}'::jsonb
      end
    from public.cardtrader_market_listing_snapshots existing
    join pg_temp.cardtrader_market_listing_refresh_scope scope
      on scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    left join pg_temp.cardtrader_market_listing_refresh_rows incoming
      on incoming.provider = existing.provider
      and incoming.external_listing_id = existing.external_listing_id
    left join pg_temp.cardtrader_market_listing_incoming_stats stats
      on stats.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    where existing.provider = v_provider
      and incoming.external_listing_id is null
    on conflict (provider, external_listing_id, removed_day) do nothing;

    get diagnostics archived_count = row_count;
    archived_count := coalesce(archived_count, 0) + coalesce(v_quantity_decreased_count, 0);

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
    archived_count := coalesce(v_quantity_decreased_count, 0);
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

  -- Homepage cache is rebuilt once in finalize_cardtrader_daily_market_refresh.
  -- Per-expansion cache refresh is too expensive for 800+ expansions.
  if p_finalize and jsonb_array_length(coalesce(v_cache_scope_blueprint_ids, '[]'::jsonb)) > 0 then
    select public.refresh_cardtrader_blueprint_listing_cache(
      v_provider,
      v_cache_scope_blueprint_ids,
      p_imported_at
    )
    into v_cache_refreshed_count;
  end if;

  cache_refreshed_count := coalesce(v_cache_refreshed_count, 0);

  if p_record_ask_observations then
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
      public.cardtrader_listing_language_for_blueprint(
        snapshot.language,
        coalesce(snapshot.properties, '{}'::jsonb),
        coalesce(snapshot.blueprint_id, snapshot.cardtrader_blueprint_id)
      ),
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
        'observationKind', 'global_market_listing_snapshot',
        'observedDay', p_imported_at::date
      ),
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
  end if;

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
    history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text || ':' || history.archive_reason,
    history.removed_day::timestamptz,
    coalesce(nullif(history.currency, ''), 'EUR'),
    coalesce(history.price, history.price_cents::numeric / 100),
    public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency),
    history.quantity,
    coalesce(nullif(history.condition, ''), 'NM'),
    public.cardtrader_listing_language_for_blueprint(
      history.language,
      coalesce(history.properties, '{}'::jsonb),
      coalesce(history.blueprint_id, history.cardtrader_blueprint_id)
    ),
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
      'externalListingId', history.external_listing_id,
      'observationKind', 'global_market_listing_removed_or_sold',
      'observedDay', history.removed_day,
      'removedDay', history.removed_day,
      'archiveReason', history.archive_reason
    ),
    now()
  from public.cardtrader_market_listing_removed_history history
  where history.provider = v_provider
    and history.removed_day = v_removed_day
    and public.cardtrader_market_is_sale_reason(history.archive_reason)
    and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
    and public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency) is not null
    and (
      jsonb_array_length(v_cache_scope_blueprint_ids) = 0
      or coalesce(history.blueprint_id, history.cardtrader_blueprint_id) in (
        select scope.blueprint_id from pg_temp.cardtrader_market_listing_refresh_scope scope
      )
    )
    and not exists (
      select 1
      from public.marketplace_price_observations existing
      where existing.source = 'cardtrader_removed_sale'
        and existing.source_item_id = history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text || ':' || history.archive_reason
    );

  if p_finalize then
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
        and public.cardtrader_market_is_sale_reason(archive_reason)
    ) touched_blueprints;
    perform public.refresh_marketplace_hot_blueprints();
  end if;

  return next;
end;
$$;

create or replace function public.finalize_cardtrader_daily_market_refresh(
  p_provider text default 'cardtrader',
  p_removed_day date default current_date - 1,
  p_imported_at timestamptz default now()
)
returns table (
  cache_refreshed_count integer,
  analytics_count integer,
  price_summary_count integer
)
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
begin
  perform set_config('statement_timeout', '0', true);
  perform set_config('lock_timeout', '0', true);

  select public.refresh_cardtrader_blueprint_listing_cache(v_provider, '[]'::jsonb, p_imported_at)
  into cache_refreshed_count;

  select public.refresh_cardtrader_blueprint_daily_analytics(coalesce(p_removed_day, current_date - 1))
  into analytics_count;

  select public.refresh_marketplace_blueprint_price_summary(null)
  into price_summary_count;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$$;

commit;
