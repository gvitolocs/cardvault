-- D000070 corrected sold pipeline: disappearance from a VALID complete-book
-- observation is an inferred_sale by default. Supersedes the D000041 strict
-- reading (inferred_sale only from by-blueprint fetches); that rule survives
-- only as observation VALIDITY:
--   * vanish archiving requires p_archive_missing AND the complete-book
--     setting (partial/cheap-25 fetches never archive);
--   * truncated fetches are refused in the API layer (shouldArchiveMissingSales);
--   * per-blueprint sanity: a quantity-stripping signature (listing count
--     holds, average qty per listing halves) freezes the blueprint and
--     downgrades vanish rows to status='pending' — never sales (Beedrill
--     389944 2026-09-17 fixture).
-- Continuity is stack-quantity aware: a vanished listing consumes the
-- seller-stack quantity delta (prev stack qty - incoming stack qty - same-id
-- drips); leftovers are listing_id_rotated, not sales. Repricing/rotation
-- with unchanged stack quantity = 0 sales; full disappearance = previous
-- quantity sold (Rapidash 115974 / Grass Energy 111246 fixtures).
-- Corrections: provisional/pending rows whose listing OR equivalent stack
-- returns within p_correction_window_days are retracted exactly once
-- (status='retracted' + observation delete, idempotent); pending rows from a
-- suspicious observation resolve on the next valid one (promotion).
-- removed_day is attributed to last_seen_at::date + 1 (bounded by the run's
-- yesterday) so delayed ghost sweeps land on the disappearance day instead of
-- spiking the sweep day.
-- History rows gain status: 'confirmed' (legacy default), 'provisional',
-- 'pending', 'retracted', 'invalid'. Sale-eligible = confirmed|provisional.
-- One-time (idempotent) September 2026 backfill:
--   * inferred_sale rows of the 2026-09-12/13 mass cutover runs (>1000 rows
--     per archiving run) are invalid — stale-Pi-clone diff artifacts;
--   * pre-cutover (<= 2026-09-10) inferred_sale / dropped_from_cheapest_25
--     rows with no same-id return, no live same-stack successor and no
--     vacation become inferred_sale (backfilled), then observations are
--     projected for every eligible unprojected row and sold_daily is fully
--     rebuilt.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;
-- The backfill hash-joins ~3M live-stack rows against ~125k history rows;
-- default work_mem spills ~10GB to temp and turns minutes into an hour.
set local work_mem = '512MB';

alter table public.cardtrader_market_listing_removed_history
  add column if not exists status text not null default 'confirmed';
alter table public.cardtrader_market_listing_removed_history
  add column if not exists resolved_at timestamptz;
create index if not exists cardtrader_removed_history_status_idx
  on public.cardtrader_market_listing_removed_history (status, removed_day);

-- ---------------------------------------------------------------------------
-- refresh_cardtrader_market_listing_snapshots (086)
-- ---------------------------------------------------------------------------

drop function if exists public.refresh_cardtrader_market_listing_snapshots(
  text, jsonb, jsonb, date, boolean, timestamptz, boolean, boolean);

create or replace function public.refresh_cardtrader_market_listing_snapshots(
  p_provider text,
  p_rows jsonb,
  p_scope_blueprint_ids jsonb default '[]'::jsonb,
  p_removed_day date default current_date - 1,
  p_archive_missing boolean default true,
  p_imported_at timestamptz default now(),
  p_finalize boolean default true,
  p_record_ask_observations boolean default false,
  p_correction_window_days integer default 10
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
    coalesce(prev.listing_count, 0) >= 10
    and coalesce(stats.listing_count, 0) >= floor(prev.listing_count * 0.85)
    and coalesce(stats.quantity_sum, 0)::numeric
        / greatest(coalesce(stats.listing_count, 0), 1)
        < (prev.listed_quantity::numeric / greatest(prev.listing_count, 1)) * 0.5
  from cardtrader_market_listing_refresh_scope scope
  left join public.cardtrader_blueprint_population_daily prev
    on prev.blueprint_id = scope.blueprint_id
   and prev.observed_day = v_removed_day
  left join cardtrader_market_listing_incoming_stats stats
    on stats.blueprint_id = scope.blueprint_id
  on conflict (blueprint_id) do update set suspicious = excluded.suspicious;

  perform public.cardtrader_upsert_seller_vacation_from_refresh(v_provider, p_imported_at);

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
          from cardtrader_market_listing_refresh_rows incoming
          join cardtrader_market_listing_refresh_scope scope
            on scope.blueprint_id = coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id)
          where scope.blueprint_id is not distinct from coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
            and h.seller_account_id = incoming.seller_account_id
            and lower(btrim(h.condition)) = lower(btrim(incoming.condition))
            and lower(btrim(h.language)) = lower(btrim(incoming.language))
            and public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '')
                is not distinct from public.cardtrader_listing_is_reverse(coalesce(incoming.properties, '{}'::jsonb), false, '')
            and public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false)
                is not distinct from public.cardtrader_listing_is_first_edition(coalesce(incoming.properties, '{}'::jsonb), false)
            and public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb))
                is not distinct from public.cardtrader_listing_is_graded(coalesce(incoming.raw_metadata, '{}'::jsonb), coalesce(incoming.properties, '{}'::jsonb))
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
    update public.cardtrader_market_listing_removed_history h
    set status = 'provisional',
        resolved_at = p_imported_at
    where h.provider = v_provider
      and h.status = 'pending'
      and h.removed_day >= v_window_from
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
        from cardtrader_market_listing_refresh_rows incoming
        where coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id)
              is not distinct from coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
          and h.seller_account_id = incoming.seller_account_id
          and lower(btrim(h.condition)) = lower(btrim(incoming.condition))
          and lower(btrim(h.language)) = lower(btrim(incoming.language))
          and public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '')
              is not distinct from public.cardtrader_listing_is_reverse(coalesce(incoming.properties, '{}'::jsonb), false, '')
          and public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false)
              is not distinct from public.cardtrader_listing_is_first_edition(coalesce(incoming.properties, '{}'::jsonb), false)
          and public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb))
              is not distinct from public.cardtrader_listing_is_graded(coalesce(incoming.raw_metadata, '{}'::jsonb), coalesce(incoming.properties, '{}'::jsonb))
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
      case when att.suspicious then 'pending' else 'provisional' end,
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
$$;


-- ---------------------------------------------------------------------------
-- sold_daily: status-gated instead of the hardcoded pre-2026-09-13 date wall
-- ---------------------------------------------------------------------------

create or replace function public.refresh_cardtrader_sold_daily(
  target_day date default null
)
returns integer
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  refreshed_count integer := 0;
begin
  perform set_config('statement_timeout', '0', true);

  if target_day is not null then
    delete from public.cardtrader_sold_daily
    where observed_day = target_day;
  else
    truncate public.cardtrader_sold_daily;
  end if;

  insert into public.cardtrader_sold_daily (
    blueprint_id,
    observed_day,
    condition,
    language,
    reverse,
    first_edition,
    graded,
    median_pkn,
    min_pkn,
    max_pkn,
    sold_qty,
    listings,
    sample_count,
    graded_comments,
    refreshed_at
  )
  select
    obs.blueprint_id,
    (obs.observed_at at time zone 'utc')::date as observed_day,
    public.cardtrader_sold_condition(obs.condition) as condition,
    public.cardtrader_sold_language(obs.language) as language,
    public.cardtrader_listing_is_reverse(
      coalesce(history.properties, '{}'::jsonb),
      obs.reverse,
      obs.foil_state
    ) as reverse,
    public.cardtrader_listing_is_first_edition(
      coalesce(history.properties, '{}'::jsonb),
      obs.first_edition
    ) as first_edition,
    obs.graded,
    percentile_cont(0.5) within group (order by obs.price_pkn) as median_pkn,
    min(obs.price_pkn) as min_pkn,
    max(obs.price_pkn) as max_pkn,
    coalesce(sum(obs.quantity), 0)::integer as sold_qty,
    count(*)::integer as listings,
    count(*)::integer as sample_count,
    case
      when obs.graded then coalesce(
        array_remove(array_agg(distinct nullif(obs.metadata->>'sellerComment', '')), null),
        '{}'::text[]
      )
      else '{}'::text[]
    end as graded_comments,
    now()
  from public.marketplace_price_observations obs
  left join public.cardtrader_market_listing_removed_history history
    on history.provider = split_part(obs.source_item_id, ':', 1)
   and history.external_listing_id = split_part(obs.source_item_id, ':', 2)
   and history.removed_day = (split_part(obs.source_item_id, ':', 3))::date
   and history.archive_reason = split_part(obs.source_item_id, ':', 4)
  left join (
    select split_part(source_item_id, ':', 2) as listing_id
    from public.marketplace_price_observations
    where source = 'cardtrader_removed_sale'
      and source_item_id like 'cardtrader:%'
      and split_part(source_item_id, ':', 4) is distinct from 'quantity_decreased'
    group by 1
    having count(distinct (observed_at at time zone 'utc')::date) = 1
  ) once_sold
    on once_sold.listing_id = split_part(obs.source_item_id, ':', 2)
  where obs.source = 'cardtrader_removed_sale'
    and obs.source_item_id like 'cardtrader:%'
    and split_part(obs.source_item_id, ':', 4) in ('inferred_sale', 'quantity_decreased')
    and coalesce(history.status, 'confirmed') in ('confirmed', 'provisional')
    and obs.price_pkn > 0
    and obs.blueprint_id is not null
    and (target_day is null or (obs.observed_at at time zone 'utc')::date = target_day)
    and public.cardtrader_sold_condition(obs.condition) is not null
    and public.cardtrader_sold_language(obs.language) is not null
    and (
      split_part(obs.source_item_id, ':', 4) = 'quantity_decreased'
      or (
        once_sold.listing_id is not null
        and not exists (
          select 1
          from public.cardtrader_market_listing_snapshots live
          where live.provider = 'cardtrader'
            and live.external_listing_id = split_part(obs.source_item_id, ':', 2)
        )
      )
    )
  group by
    obs.blueprint_id,
    (obs.observed_at at time zone 'utc')::date,
    public.cardtrader_sold_condition(obs.condition),
    public.cardtrader_sold_language(obs.language),
    public.cardtrader_listing_is_reverse(
      coalesce(history.properties, '{}'::jsonb),
      obs.reverse,
      obs.foil_state
    ),
    public.cardtrader_listing_is_first_edition(
      coalesce(history.properties, '{}'::jsonb),
      obs.first_edition
    ),
    obs.graded;

  get diagnostics refreshed_count = row_count;
  return coalesce(refreshed_count, 0);
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
  v_day date := coalesce(p_removed_day, current_date - 1);
begin
  perform set_config('statement_timeout', '0', true);

  select public.refresh_cardtrader_blueprint_listing_cache(v_provider, '[]'::jsonb, p_imported_at)
  into cache_refreshed_count;

  perform public.annotate_cardtrader_removed_sale_observations(v_day);
  perform public.cardtrader_reclassify_vacation_vanished_sellers(v_provider, v_day);
  -- Full rebuild: corrections and delayed attribution can touch any day.
  perform public.refresh_cardtrader_sold_daily(null);

  select public.refresh_cardtrader_blueprint_daily_analytics(v_day)
  into analytics_count;

  select public.refresh_marketplace_blueprint_price_summary(null)
  into price_summary_count;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$$;


-- ---------------------------------------------------------------------------
-- One-time (idempotent) September 2026 backfill
-- ---------------------------------------------------------------------------

-- Shared set-based inputs: grouped live stacks, live listing ids, sellers on
-- vacation, and an index that makes observation idempotency probes cheap.
create temp table cardtrader_live_stacks on commit drop as
select
  coalesce(s.blueprint_id, s.cardtrader_blueprint_id) as blueprint_id,
  s.seller_account_id,
  lower(btrim(s.condition)) as cond,
  lower(btrim(s.language)) as lang,
  public.cardtrader_listing_is_reverse(coalesce(s.properties, '{}'::jsonb), false, '') as rev,
  public.cardtrader_listing_is_first_edition(coalesce(s.properties, '{}'::jsonb), false) as fe,
  public.cardtrader_listing_is_graded(coalesce(s.raw_metadata, '{}'::jsonb), coalesce(s.properties, '{}'::jsonb)) as gr
from public.cardtrader_market_listing_snapshots s
where s.provider = 'cardtrader'
  and coalesce(s.seller_account_id, '') <> '';
create index on cardtrader_live_stacks (blueprint_id, seller_account_id, cond, lang, rev, fe, gr);

create temp table cardtrader_vacation_sellers on commit drop as
select distinct seller_account_id
from public.cardtrader_seller_vacation
where provider = 'cardtrader'
  and cardtrader_seller_is_on_vacation(provider, seller_account_id);

create index if not exists marketplace_price_observations_source_item_idx
  on public.marketplace_price_observations (source_item_id);

-- 1) Mass cutover runs (>1000 rows per archiving run) are stale-Pi-clone
--    diff artifacts, never market sales.
create temp table cardtrader_artifact_runs on commit drop as
select archive_metadata->>'refreshImportedAt' as run_ts
from public.cardtrader_market_listing_removed_history
where provider = 'cardtrader'
  and removed_day between '2026-09-11' and '2026-09-13'
  and archive_reason = 'inferred_sale'
  and coalesce(seller_account_id, '') <> ''
group by 1
having count(*) > 1000;

update public.cardtrader_market_listing_removed_history h
set status = 'invalid',
    resolved_at = now()
from cardtrader_artifact_runs r
where h.provider = 'cardtrader'
  and h.archive_reason = 'inferred_sale'
  and h.removed_day between '2026-09-11' and '2026-09-13'
  and coalesce(h.archive_metadata->>'refreshImportedAt', '') = r.run_ts
  and h.status = 'confirmed';

-- 2) Precompute the facet fingerprint once per candidate row (single pass —
--    the jsonb facet helpers re-fetch TOASTed properties on every call), then
--    classify set-based. listing_id_rotated rows are intentionally left alone
--    (their stack had a live successor; the successor's own row carries the
--    units if the stack later vanished).
create temp table cardtrader_pre_cutover on commit drop as
select
  h.id,
  h.external_listing_id,
  coalesce(h.blueprint_id, h.cardtrader_blueprint_id) as blueprint_id,
  h.seller_account_id,
  h.quantity,
  lower(btrim(h.condition)) as cond,
  lower(btrim(h.language)) as lang,
  public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '') as rev,
  public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false) as fe,
  public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb)) as gr,
  exists (
    select 1
    from public.cardtrader_market_listing_snapshots s
    where s.provider = 'cardtrader'
      and s.external_listing_id = h.external_listing_id
  ) as id_back_live,
  h.archive_reason
from public.cardtrader_market_listing_removed_history h
where h.provider = 'cardtrader'
  and h.removed_day < '2026-09-11'
  and h.archive_reason in ('inferred_sale', 'dropped_from_cheapest_25')
  and h.status = 'confirmed'
  and coalesce(h.seller_account_id, '') <> ''
  and coalesce(h.quantity, 0) > 0;
create index on cardtrader_pre_cutover (blueprint_id, seller_account_id, cond, lang, rev, fe, gr);

with backfill as (
  select c.id
  from cardtrader_pre_cutover c
  where not c.id_back_live
    and c.seller_account_id not in (select seller_account_id from cardtrader_vacation_sellers)
    and not exists (
      select 1
      from cardtrader_live_stacks ls
      where ls.blueprint_id is not distinct from c.blueprint_id
        and ls.seller_account_id = c.seller_account_id
        and ls.cond = c.cond
        and ls.lang = c.lang
        and ls.rev = c.rev
        and ls.fe = c.fe
        and ls.gr = c.gr
    )
)
update public.cardtrader_market_listing_removed_history h
set archive_reason = 'inferred_sale',
    archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedFrom', h.archive_reason,
      'reclassifiedBecause', 'backfill_disappearance_inferred_sale_d000070'
    )
where h.id in (select id from backfill);

-- 2b) Pre-cutover inferred_sale rows that FAIL continuity (same id back in
--     the book, equivalent seller stack still live, or seller on vacation)
--     are not sales — invalidate them the way the runtime correction pass
--     would (mirrors T4c/T4e classification and the retraction semantics).
with continuity_found as (
  select c.id
  from cardtrader_pre_cutover c
  where c.archive_reason = 'inferred_sale'
    and (
      c.id_back_live
      or c.seller_account_id in (select seller_account_id from cardtrader_vacation_sellers)
      or exists (
        select 1
        from cardtrader_live_stacks ls
        where ls.blueprint_id is not distinct from c.blueprint_id
          and ls.seller_account_id = c.seller_account_id
          and ls.cond = c.cond
          and ls.lang = c.lang
          and ls.rev = c.rev
          and ls.fe = c.fe
          and ls.gr = c.gr
      )
    )
)
update public.cardtrader_market_listing_removed_history h
set status = 'invalid',
    resolved_at = now(),
    archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedBecause', 'backfill_continuity_found_d000070'
    )
where h.id in (select id from continuity_found);

-- 3) Project observations for every eligible unprojected row (idempotent via
--    source_item_id), then rebuild the sold graph.
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
where history.provider = 'cardtrader'
  and history.removed_day <= current_date - 1
  and history.removed_day >= current_date - 60
  and history.status in ('confirmed', 'provisional')
  and history.archive_reason in ('inferred_sale', 'quantity_decreased')
  and coalesce(history.blueprint_id, history.cardtrader_blueprint_id) is not null
  and coalesce(history.quantity, 0) > 0
  and public.marketplace_price_pkn_from_cardtrader(history.price, history.price_cents, history.currency) is not null
  and not exists (
    select 1
    from public.marketplace_price_observations existing
    where existing.source = 'cardtrader_removed_sale'
      and existing.source_item_id = history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text || ':' || history.archive_reason
  );

select public.refresh_cardtrader_sold_daily(null) as sold_daily_rows;
select public.refresh_marketplace_blueprint_price_summary(null) as price_summary_rows;

commit;
