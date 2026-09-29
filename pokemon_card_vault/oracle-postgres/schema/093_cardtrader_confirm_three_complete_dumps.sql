-- 093: CardTrader sale confirmation over 3 complete dumps + empty/shrunk
-- book guard.
--
-- Why (audit 2026-09-24): a listing missing from ONE dump was archived as a
-- counted sale. Listings routinely drop out of a dump for a day (API flake,
-- seller hiding the listing) and come back; since 2026-09-21 the nightly run
-- also aborts part-way (rejected API token), leaving partial books.
--
-- What changes in refresh_cardtrader_market_listing_snapshots (body = 091
-- otherwise, byte for byte):
--   * Vanished listings are archived as 'pending' (not counted) with
--     confirmationRequired=3, completeAbsences=1 (0 for suspicious books).
--   * Each later complete, non-suspicious dump that still sees the listing
--     gone (and no equivalent seller-stack successor) adds 1, once per run
--     day. On the 3rd the row becomes 'provisional' (counted); the existing
--     observation projection then emits it dated to removed_day, the FIRST
--     missing day.
--   * Unchanged: ghost cleanup still drops the listing from the live book at
--     once; the corrections block still retracts pending AND provisional rows
--     whose listing or seller stack returns; incomplete dumps never touch
--     any of this (v_can_archive).
--   * Sanity also freezes (a) an empty book for a blueprint with live
--     listings and (b) a book that lost more than half its listings.
--   * Legacy sanity-only pending rows (no confirmationRequired) keep the old
--     one-step promotion.
--
-- Model-checked: formal/confirm3/Confirm3.tla (TLC, all safety invariants
-- hold; "counted => really sold" fails by design: a listing hidden for 3
-- complete dumps is counted until it returns, then retracted).

begin;
set local statement_timeout = 0;
set local lock_timeout = 0;

CREATE OR REPLACE FUNCTION public.refresh_cardtrader_market_listing_snapshots(p_provider text, p_rows jsonb, p_scope_blueprint_ids jsonb DEFAULT '[]'::jsonb, p_removed_day date DEFAULT (CURRENT_DATE - 1), p_archive_missing boolean DEFAULT true, p_imported_at timestamp with time zone DEFAULT now(), p_finalize boolean DEFAULT true, p_record_ask_observations boolean DEFAULT false, p_correction_window_days integer DEFAULT 10)
 RETURNS TABLE(archived_count integer, deleted_count integer, upserted_count integer, cache_refreshed_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '0'
 SET jit TO 'off'
AS $function$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_scope_blueprint_ids jsonb := coalesce(p_scope_blueprint_ids, '[]'::jsonb);
  v_removed_day date := coalesce(p_removed_day, current_date - 1);
  v_window_days integer := greatest(coalesce(p_correction_window_days, 10), 1);
  v_window_from date := current_date - greatest(coalesce(p_correction_window_days, 10), 1);
  v_complete_book boolean := current_setting('app.cardtrader_complete_book', true) in ('1', 'true', 'on');
  v_can_archive boolean := p_archive_missing and v_complete_book;
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

  create temp table if not exists cardtrader_market_listing_refresh_rows (
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

  create temp table if not exists cardtrader_market_listing_refresh_scope (
    blueprint_id bigint primary key
  ) on commit drop;

  create temp table if not exists cardtrader_market_listing_incoming_stats (
    blueprint_id bigint primary key,
    listing_count integer not null,
    quantity_sum integer not null default 0,
    ceiling_price numeric
  ) on commit drop;

  create temp table if not exists cardtrader_refresh_sanity (
    blueprint_id bigint primary key,
    suspicious boolean not null
  ) on commit drop;

  -- 091: seller-stack facet keys computed once per incoming row. The
  -- correlated EXISTS used to re-run the three facet helpers on every
  -- (history row x incoming row) pair: 9.7 min for one 10k-row expansion.
  create temp table if not exists cardtrader_refresh_stack_keys (
    blueprint_id bigint not null,
    seller_account_id text not null,
    condition_key text not null,
    language_key text not null,
    is_reverse boolean,
    is_first_edition boolean,
    is_graded boolean
  ) on commit drop;

  create index if not exists cardtrader_refresh_stack_keys_idx
    on cardtrader_refresh_stack_keys (blueprint_id, seller_account_id, condition_key, language_key);

  create temp table if not exists cardtrader_retract_now (
    history_id uuid primary key,
    provider text not null,
    external_listing_id text not null,
    removed_day date not null
  ) on commit drop;

  truncate table cardtrader_market_listing_refresh_rows;
  truncate table cardtrader_market_listing_refresh_scope;
  truncate table cardtrader_market_listing_incoming_stats;
  truncate table cardtrader_refresh_sanity;
  truncate table cardtrader_retract_now;
  truncate table cardtrader_refresh_stack_keys;

  insert into cardtrader_market_listing_refresh_rows (
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

  insert into cardtrader_market_listing_refresh_scope (blueprint_id)
  select distinct value::bigint
  from jsonb_array_elements_text(v_scope_blueprint_ids) as scope(value)
  where value ~ '^[0-9]+$'
  on conflict do nothing;

  insert into cardtrader_market_listing_refresh_scope (blueprint_id)
  select distinct coalesce(blueprint_id, cardtrader_blueprint_id)
  from cardtrader_market_listing_refresh_rows
  where coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  on conflict do nothing;

  insert into cardtrader_market_listing_incoming_stats (
    blueprint_id,
    listing_count,
    quantity_sum,
    ceiling_price
  )
  select
    coalesce(blueprint_id, cardtrader_blueprint_id) as blueprint_id,
    count(*)::integer,
    coalesce(sum(quantity), 0)::integer,
    case
      when current_setting('app.cardtrader_complete_book', true) in ('1', 'true', 'on')
        then null
      else max(coalesce(price, price_cents::numeric / 100))
    end
  from cardtrader_market_listing_refresh_rows
  where coalesce(blueprint_id, cardtrader_blueprint_id) is not null
  group by coalesce(blueprint_id, cardtrader_blueprint_id)
  on conflict do nothing;

  -- Observation sanity: a quantity-stripping signature (listing count holds,
  -- average quantity per listing halves) invalidates disappearance inference
  -- for that blueprint. Beedrill 389944 2026-09-17: 113 listings/1277 qty ->
  -- 115/345 -> recovered 119/1294 with zero real vanish events.
  insert into cardtrader_refresh_sanity (blueprint_id, suspicious)
  select
    scope.blueprint_id,
    (
      -- 086: stripped-quantity signature.
      coalesce(prev.listing_count, 0) >= 10
      and coalesce(stats.listing_count, 0) >= floor(prev.listing_count * 0.85)
      and coalesce(stats.quantity_sum, 0)::numeric
          / greatest(coalesce(stats.listing_count, 0), 1)
          < (prev.listed_quantity::numeric / greatest(prev.listing_count, 1)) * 0.5
    )
    -- 093: an empty book for a blueprint that has live listings is an API
    -- failure, not a sell-out. Freeze it: no vanish, no cleanup, no counting.
    or (
      coalesce(stats.listing_count, 0) = 0
      and exists (
        select 1 from public.cardtrader_market_listing_snapshots live
        where live.provider = v_provider
          and coalesce(live.blueprint_id, live.cardtrader_blueprint_id) = scope.blueprint_id
      )
    )
    -- 093: a book that lost more than half its listings overnight is almost
    -- always a truncated fetch.
    or (
      coalesce(prev.listing_count, 0) >= 10
      and coalesce(stats.listing_count, 0) < prev.listing_count * 0.5
    )
  from cardtrader_market_listing_refresh_scope scope
  left join public.cardtrader_blueprint_population_daily prev
    on prev.blueprint_id = scope.blueprint_id
   and prev.observed_day = v_removed_day
  left join cardtrader_market_listing_incoming_stats stats
    on stats.blueprint_id = scope.blueprint_id
  on conflict (blueprint_id) do update set suspicious = excluded.suspicious;

  perform public.cardtrader_upsert_seller_vacation_from_refresh(v_provider, p_imported_at);

  insert into cardtrader_refresh_stack_keys (
    blueprint_id, seller_account_id, condition_key, language_key,
    is_reverse, is_first_edition, is_graded
  )
  select distinct
    coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id),
    incoming.seller_account_id,
    lower(btrim(incoming.condition)),
    lower(btrim(incoming.language)),
    public.cardtrader_listing_is_reverse(coalesce(incoming.properties, '{}'::jsonb), false, ''),
    public.cardtrader_listing_is_first_edition(coalesce(incoming.properties, '{}'::jsonb), false),
    public.cardtrader_listing_is_graded(coalesce(incoming.raw_metadata, '{}'::jsonb), coalesce(incoming.properties, '{}'::jsonb))
  from cardtrader_market_listing_refresh_rows incoming
  where coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id) is not null;

  analyze cardtrader_refresh_stack_keys;
  analyze cardtrader_market_listing_refresh_rows;
  analyze cardtrader_market_listing_refresh_scope;

  if v_can_archive and exists (select 1 from cardtrader_market_listing_refresh_scope) then
    -- ------------------------------------------------------------------
    -- Corrections first: retract provisional/pending episodes whose listing
    -- id OR equivalent seller stack returned within the correction window.
    -- Idempotent: already-retracted rows never match the open filter.
    -- ------------------------------------------------------------------
    insert into cardtrader_retract_now (history_id, provider, external_listing_id, removed_day)
    select h.id, h.provider, h.external_listing_id, h.removed_day
    from public.cardtrader_market_listing_removed_history h
    where h.provider = v_provider
      and h.status in ('provisional', 'pending')
      and h.removed_day >= v_window_from
      and h.seller_account_id <> ''
      and (
        exists (
          select 1
          from cardtrader_market_listing_refresh_rows incoming
          join cardtrader_market_listing_refresh_scope scope
            on scope.blueprint_id = coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id)
          where incoming.external_listing_id = h.external_listing_id
        )
        or (
          -- A residual left by reconcile_cardtrader_seller_stack_continuity has
          -- already had its successor units credited; the surviving quantity is
          -- a genuine partial sale and must not be retracted wholesale here.
          not (h.archive_metadata ? 'continuityQuantity')
          and exists (
          select 1
          from cardtrader_refresh_stack_keys k
          where k.blueprint_id = coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
            and k.seller_account_id = h.seller_account_id
            and k.condition_key = lower(btrim(h.condition))
            and k.language_key = lower(btrim(h.language))
            and k.is_reverse is not distinct from public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '')
            and k.is_first_edition is not distinct from public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false)
            and k.is_graded is not distinct from public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb))
        ))
      )
    on conflict (history_id) do nothing;

    update public.cardtrader_market_listing_removed_history h
    set status = 'retracted',
        resolved_at = p_imported_at
    from cardtrader_retract_now r
    where h.id = r.history_id
      and h.status in ('provisional', 'pending');

    delete from public.marketplace_price_observations o
    using cardtrader_retract_now r
    where o.source = 'cardtrader_removed_sale'
      and split_part(o.source_item_id, ':', 1) = r.provider
      and split_part(o.source_item_id, ':', 2) = r.external_listing_id
      and split_part(o.source_item_id, ':', 3) = r.removed_day::text;

    -- Promote pending rows on now-valid observations: still absent and no
    -- equivalent stack successor => the disappearance stands (provisional).
    -- 093: legacy sanity-only pending rows keep this one-step promotion.
    update public.cardtrader_market_listing_removed_history h
    set status = 'provisional',
        resolved_at = p_imported_at
    where h.provider = v_provider
      and h.status = 'pending'
      and h.removed_day >= v_window_from
      and not (coalesce(h.archive_metadata, '{}'::jsonb) ? 'confirmationRequired')
      and exists (
        select 1
        from cardtrader_market_listing_refresh_scope scope
        where scope.blueprint_id is not distinct from coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
      )
      and not exists (
        select 1
        from cardtrader_refresh_sanity sanity
        where sanity.blueprint_id = coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
          and sanity.suspicious
      )
      and not exists (
        select 1
        from cardtrader_market_listing_refresh_rows incoming
        where incoming.external_listing_id = h.external_listing_id
      )
      and not exists (
        select 1
        from cardtrader_refresh_stack_keys k
        where k.blueprint_id = coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
          and k.seller_account_id = h.seller_account_id
          and k.condition_key = lower(btrim(h.condition))
          and k.language_key = lower(btrim(h.language))
          and k.is_reverse is not distinct from public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '')
          and k.is_first_edition is not distinct from public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false)
          and k.is_graded is not distinct from public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb))
      );

    -- 093: 3-complete-dump confirmation. Every complete, non-suspicious dump
    -- that still sees the listing gone (and no equivalent stack successor)
    -- adds one complete absence, at most once per run day. The third makes
    -- the sale countable (provisional), still attributed to removed_day, the
    -- first missing day. Incomplete dumps never reach this block
    -- (v_can_archive), and suspicious/zero-row books are excluded below.
    update public.cardtrader_market_listing_removed_history h
    set archive_metadata = h.archive_metadata || jsonb_build_object(
          'completeAbsences', coalesce((h.archive_metadata->>'completeAbsences')::int, 0) + 1,
          'lastAbsentRunDay', v_removed_day),
        status = case
          when coalesce((h.archive_metadata->>'completeAbsences')::int, 0) + 1
               >= coalesce((h.archive_metadata->>'confirmationRequired')::int, 3)
          then 'provisional' else h.status end,
        resolved_at = case
          when coalesce((h.archive_metadata->>'completeAbsences')::int, 0) + 1
               >= coalesce((h.archive_metadata->>'confirmationRequired')::int, 3)
          then p_imported_at else h.resolved_at end
    where h.provider = v_provider
      and h.status = 'pending'
      and h.removed_day >= v_window_from
      and h.archive_metadata ? 'confirmationRequired'
      and coalesce((h.archive_metadata->>'lastAbsentRunDay')::date, '-infinity'::date) < v_removed_day
      and exists (
        select 1
        from cardtrader_market_listing_refresh_scope scope
        where scope.blueprint_id is not distinct from coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
      )
      and not exists (
        select 1
        from cardtrader_refresh_sanity sanity
        where sanity.blueprint_id = coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
          and sanity.suspicious
      )
      and not exists (
        select 1
        from cardtrader_market_listing_refresh_rows incoming
        where incoming.external_listing_id = h.external_listing_id
      )
      and not exists (
        select 1
        from cardtrader_refresh_stack_keys k
        where k.blueprint_id = coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
          and k.seller_account_id = h.seller_account_id
          and k.condition_key = lower(btrim(h.condition))
          and k.language_key = lower(btrim(h.language))
          and k.is_reverse is not distinct from public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '')
          and k.is_first_edition is not distinct from public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false)
          and k.is_graded is not distinct from public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb))
      );
  end if;

  -- Same-id quantity drips on still-present listings: sale-shaped and robust
  -- against book validity, so these stay ungated by the complete-book flag
  -- except on sanity-frozen blueprints.
  if exists (select 1 from cardtrader_market_listing_refresh_scope) then
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
      status,
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
      'provisional',
      'quantity_decreased',
      jsonb_build_object(
        'refreshImportedAt', p_imported_at,
        'previousQuantity', existing.quantity,
        'currentQuantity', incoming.quantity
      )
    from public.cardtrader_market_listing_snapshots existing
    join cardtrader_market_listing_refresh_rows incoming
      on incoming.provider = existing.provider
      and incoming.external_listing_id = existing.external_listing_id
    join cardtrader_market_listing_refresh_scope scope
      on scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    where existing.provider = v_provider
      and existing.quantity > incoming.quantity
      and not public.cardtrader_listing_is_on_vacation(incoming.raw_metadata)
      and not public.cardtrader_seller_is_on_vacation(v_provider, existing.seller_account_id)
      and not exists (
        select 1
        from cardtrader_refresh_sanity sanity
        where sanity.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
          and sanity.suspicious
      )
    on conflict (provider, external_listing_id, removed_day) do nothing;

    get diagnostics v_quantity_decreased_count = row_count;
  end if;

  -- Vanish archiving: only valid complete-book observations. Stack-quantity
  -- attribution: the vanished listing consumes the seller-stack delta
  -- (previous stack qty - incoming stack qty - same-id drips), leftovers are
  -- rotation, not sales. Status 'provisional' (counted) for valid scopes,
  -- 'pending' (not counted) for sanity-frozen scopes — frozen books keep
  -- their snapshot rows untouched.
  if v_can_archive and exists (select 1 from cardtrader_market_listing_refresh_scope) then
    drop table if exists cardtrader_vanish_attribution;
    create temp table cardtrader_vanish_attribution on commit drop as
    with prev_stack as (
      select
        coalesce(s.blueprint_id, s.cardtrader_blueprint_id) as blueprint_id,
        s.seller_account_id,
        lower(btrim(s.condition)) as cond,
        lower(btrim(s.language)) as lang,
        public.cardtrader_listing_is_reverse(coalesce(s.properties, '{}'::jsonb), false, '') as rev,
        public.cardtrader_listing_is_first_edition(coalesce(s.properties, '{}'::jsonb), false) as fe,
        public.cardtrader_listing_is_graded(coalesce(s.raw_metadata, '{}'::jsonb), coalesce(s.properties, '{}'::jsonb)) as gr,
        sum(s.quantity) as qty
      from public.cardtrader_market_listing_snapshots s
      join cardtrader_market_listing_refresh_scope scope
        on scope.blueprint_id = coalesce(s.blueprint_id, s.cardtrader_blueprint_id)
      where s.provider = v_provider
        and coalesce(s.seller_account_id, '') <> ''
      group by 1, 2, 3, 4, 5, 6, 7
    ),
    in_stack as (
      select
        coalesce(r.blueprint_id, r.cardtrader_blueprint_id) as blueprint_id,
        r.seller_account_id,
        lower(btrim(r.condition)) as cond,
        lower(btrim(r.language)) as lang,
        public.cardtrader_listing_is_reverse(coalesce(r.properties, '{}'::jsonb), false, '') as rev,
        public.cardtrader_listing_is_first_edition(coalesce(r.properties, '{}'::jsonb), false) as fe,
        public.cardtrader_listing_is_graded(coalesce(r.raw_metadata, '{}'::jsonb), coalesce(r.properties, '{}'::jsonb)) as gr,
        sum(r.quantity) as qty
      from cardtrader_market_listing_refresh_rows r
      group by 1, 2, 3, 4, 5, 6, 7
    ),
    drip_stack as (
      select
        coalesce(s.blueprint_id, s.cardtrader_blueprint_id) as blueprint_id,
        s.seller_account_id,
        lower(btrim(s.condition)) as cond,
        lower(btrim(s.language)) as lang,
        public.cardtrader_listing_is_reverse(coalesce(s.properties, '{}'::jsonb), false, '') as rev,
        public.cardtrader_listing_is_first_edition(coalesce(s.properties, '{}'::jsonb), false) as fe,
        public.cardtrader_listing_is_graded(coalesce(s.raw_metadata, '{}'::jsonb), coalesce(s.properties, '{}'::jsonb)) as gr,
        sum(greatest(s.quantity - r.quantity, 0)) as qty
      from public.cardtrader_market_listing_snapshots s
      join cardtrader_market_listing_refresh_rows r
        on r.provider = s.provider
       and r.external_listing_id = s.external_listing_id
      join cardtrader_market_listing_refresh_scope scope
        on scope.blueprint_id = coalesce(s.blueprint_id, s.cardtrader_blueprint_id)
      where s.provider = v_provider
      group by 1, 2, 3, 4, 5, 6, 7
    ),
    vanished as (
      select
        existing.external_listing_id,
        coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id) as blueprint_id,
        existing.seller_account_id,
        lower(btrim(existing.condition)) as cond,
        lower(btrim(existing.language)) as lang,
        public.cardtrader_listing_is_reverse(coalesce(existing.properties, '{}'::jsonb), false, '') as rev,
        public.cardtrader_listing_is_first_edition(coalesce(existing.properties, '{}'::jsonb), false) as fe,
        public.cardtrader_listing_is_graded(coalesce(existing.raw_metadata, '{}'::jsonb), coalesce(existing.properties, '{}'::jsonb)) as gr,
        existing.quantity,
        least(v_removed_day, (existing.last_seen_at at time zone 'utc')::date + 1) as removed_day,
        coalesce(sanity.suspicious, false) as suspicious
      from public.cardtrader_market_listing_snapshots existing
      join cardtrader_market_listing_refresh_scope scope
        on scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
      left join cardtrader_market_listing_refresh_rows incoming
        on incoming.provider = existing.provider
       and incoming.external_listing_id = existing.external_listing_id
      left join cardtrader_refresh_sanity sanity
        on sanity.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
      where existing.provider = v_provider
        and incoming.external_listing_id is null
        and not public.cardtrader_seller_is_on_vacation(v_provider, existing.seller_account_id)
        and coalesce(existing.seller_account_id, '') <> ''
    )
    select
      v.*,
      case when v.suspicious then 0 else
        greatest(
          coalesce(ps.qty, 0) - coalesce(isn.qty, 0) - coalesce(dr.qty, 0),
          0
        )
      end as stack_delta,
      coalesce(ps.qty, 0) as stack_qty_before,
      coalesce(isn.qty, 0) as stack_qty_after,
      coalesce(
        sum(v.quantity) over (
          partition by v.blueprint_id, v.seller_account_id, v.cond, v.lang, v.rev, v.fe, v.gr
          order by v.external_listing_id
          rows between unbounded preceding and 1 preceding
        ),
      0) as stack_delta_consumed_before
    from vanished v
    left join prev_stack ps
      on ps.blueprint_id = v.blueprint_id and ps.seller_account_id = v.seller_account_id
     and ps.cond = v.cond and ps.lang = v.lang and ps.rev = v.rev and ps.fe = v.fe and ps.gr = v.gr
    left join in_stack isn
      on isn.blueprint_id = v.blueprint_id and isn.seller_account_id = v.seller_account_id
     and isn.cond = v.cond and isn.lang = v.lang and isn.rev = v.rev and isn.fe = v.fe and isn.gr = v.gr
    left join drip_stack dr
      on dr.blueprint_id = v.blueprint_id and dr.seller_account_id = v.seller_account_id
     and dr.cond = v.cond and dr.lang = v.lang and dr.rev = v.rev and dr.fe = v.fe and dr.gr = v.gr;

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
      status,
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
      case
        when att.suspicious then existing.quantity
        else greatest(least(existing.quantity, att.stack_delta - att.stack_delta_consumed_before), 0)
      end,
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
      att.removed_day,
      'pending',  -- 093: counted only after 3 complete absences
      case
        when att.suspicious then 'inferred_sale'
        when greatest(least(existing.quantity, att.stack_delta - att.stack_delta_consumed_before), 0) > 0
          then 'inferred_sale'
        else 'listing_id_rotated'
      end,
      jsonb_build_object(
        'refreshImportedAt', p_imported_at,
        'incomingListingCount', coalesce(stats.listing_count, 0),
        'incomingCeilingPrice', stats.ceiling_price,
        'originalQuantity', existing.quantity,
        'stackQuantityBefore', att.stack_qty_before,
        'stackQuantityAfter', att.stack_qty_after,
        'attribution', case
          when att.suspicious then 'observation_pending_sanity'
          else 'stack_quantity_delta'
        end
      ) || case
        when not att.suspicious
          and greatest(least(existing.quantity, att.stack_delta - att.stack_delta_consumed_before), 0) = 0
          then jsonb_build_object('reclassifiedBecause', 'seller_stack_quantity_unchanged')
        else '{}'::jsonb
      end
      -- 093: confirmation bookkeeping. A suspicious book is not a valid
      -- observation, so it starts at 0 complete absences.
      || jsonb_build_object(
        'confirmationRequired', 3,
        'completeAbsences', case when att.suspicious then 0 else 1 end,
        'lastAbsentRunDay', case when att.suspicious then null else v_removed_day end
      )
    from public.cardtrader_market_listing_snapshots existing
    join cardtrader_vanish_attribution att
      on att.external_listing_id = existing.external_listing_id
     and att.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    left join cardtrader_market_listing_refresh_rows incoming
      on incoming.provider = existing.provider
     and incoming.external_listing_id = existing.external_listing_id
    left join cardtrader_market_listing_incoming_stats stats
      on stats.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
    where existing.provider = v_provider
      and incoming.external_listing_id is null
      and not public.cardtrader_seller_is_on_vacation(v_provider, existing.seller_account_id)
      and not exists (
        select 1
        from public.cardtrader_market_listing_removed_history open
        where open.provider = v_provider
          and open.external_listing_id = existing.external_listing_id
          and open.status in ('provisional', 'pending')
          and open.removed_day >= v_window_from
      )
    on conflict (provider, external_listing_id, removed_day) do nothing;

    get diagnostics archived_count = row_count;
    archived_count := coalesce(archived_count, 0) + coalesce(v_quantity_decreased_count, 0);

    -- Ghost cleanup: a valid disappearance leaves no stale row in the live
    -- book. Sanity-frozen blueprints keep their last-good book untouched.
    delete from public.cardtrader_market_listing_snapshots existing
    using cardtrader_market_listing_refresh_scope scope
    where existing.provider = v_provider
      and scope.blueprint_id = coalesce(existing.blueprint_id, existing.cardtrader_blueprint_id)
      and not exists (
        select 1
        from cardtrader_market_listing_refresh_rows incoming
        where incoming.provider = existing.provider
          and incoming.external_listing_id = existing.external_listing_id
      )
      and not public.cardtrader_seller_is_on_vacation(v_provider, existing.seller_account_id)
      and not exists (
        select 1
        from cardtrader_refresh_sanity sanity
        where sanity.blueprint_id = scope.blueprint_id
          and sanity.suspicious
      );

    get diagnostics deleted_count = row_count;
  else
    archived_count := coalesce(v_quantity_decreased_count, 0);
    deleted_count := 0;
  end if;

  -- Upsert the live book, sanity-frozen blueprints excluded.
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
  from cardtrader_market_listing_refresh_rows incoming
  where not exists (
    select 1
    from cardtrader_refresh_sanity sanity
    where sanity.blueprint_id = coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id)
      and sanity.suspicious
  )
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
  from cardtrader_market_listing_refresh_scope scope
  into v_cache_scope_blueprint_ids;

  -- A complete, valid refresh can prove continuity for the previous
  -- observation. Partial or sanity-frozen books must not retract sales.
  if v_can_archive
     and not exists (
       select 1
       from cardtrader_refresh_sanity sanity
       where sanity.suspicious
     ) then
    perform public.reconcile_cardtrader_seller_stack_continuity(
      v_provider,
      v_window_from,
      v_removed_day,
      v_cache_scope_blueprint_ids
    );
  end if;

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
      public.cardtrader_listing_is_reverse(
        coalesce(snapshot.properties, '{}'::jsonb),
        false,
        coalesce(snapshot.properties->>'foil_state', snapshot.properties->>'foilState', '')
      ),
      public.cardtrader_listing_is_first_edition(
        coalesce(snapshot.properties, '{}'::jsonb),
        false
      ),
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
    join cardtrader_market_listing_refresh_scope scope
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

  -- Removed-sale observations for every sale-eligible history row this (or a
  -- previous) refresh produced, up to the current removed_day. Status gates
  -- counting: pending/retracted/invalid rows never project. Historical
  -- attribution (removed_day <= v_removed_day) keeps delayed ghost sweeps on
  -- their disappearance day.
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
    public.cardtrader_listing_is_reverse(
      coalesce(history.properties, '{}'::jsonb),
      false,
      coalesce(history.properties->>'foil_state', history.properties->>'foilState', '')
    ),
    public.cardtrader_listing_is_first_edition(
      coalesce(history.properties, '{}'::jsonb),
      false
    ),
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
      'archiveReason', history.archive_reason,
      'status', history.status
    ),
    now()
  from public.cardtrader_market_listing_removed_history history
  where history.provider = v_provider
    and history.removed_day <= v_removed_day
    and history.removed_day > v_removed_day - 60
    and history.status in ('confirmed', 'provisional')
    and public.cardtrader_market_is_sale_reason(history.archive_reason)
    and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
    and coalesce(history.quantity, 0) > 0
    and public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency) is not null
    and (
      jsonb_array_length(v_cache_scope_blueprint_ids) = 0
      or coalesce(history.blueprint_id, history.cardtrader_blueprint_id) in (
        select scope.blueprint_id from cardtrader_market_listing_refresh_scope scope
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
          select scope.blueprint_id from cardtrader_market_listing_refresh_scope scope
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
$function$;

commit;
