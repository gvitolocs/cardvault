-- 103: a seller store that withdraws wholesale is not a sale.
--
-- Why (investigation 2026-09-30, after 101/102): from 2026-09-18 on, 60-85%
-- of the daily sold-graph units came from sellers whose whole store left the
-- CardTrader book. The Wasteland Gaming lost 16,045 listings (70,362 copies)
-- on 2026-09-23 and kept 13; ParadoxTCG 7,062 (25,497 copies), 11 left;
-- Leumas Card Craze 1,522 (12,684 copies), 0 left. The sold graph went from
-- ~6k units/day (09-15..17) to 232,741 on 09-21. 075's vacation rule never
-- fired: it needs zero live listings, only looks at inferred_sale, and a
-- seller whose listings vanished cannot be seen with on_vacation=true.
--
-- Stores wind down over several dumps (Wasteland: 09-21 19%, 09-22 8.5%,
-- 09-23 87%, 09-25 99.6% of what was left), so the rule looks at a window:
-- for removed_day D, a seller whose book held at least 500 listings and who
-- lost at least 80% of it within [D-6, D] has withdrawn the store (Giuseppe
-- 2026-09-30: both thresholds required, 7-day window). All of that seller's
-- vanishings in the window (inferred_sale, young_listing_removed) are
-- archived as archive_reason='seller_store_withdrawn' (not a sale reason:
-- history kept for audit, never projected, never in sold_daily).
-- quantity_decreased rows stay: those listings are still live.
--   vanished    = listings gone in the window as inferred_sale,
--                 young_listing_removed or already seller_store_withdrawn
--                 (so a flagged store keeps qualifying on the next days)
--   book_before = listings gone in the window (every archive reason except
--                 same-id quantity drips) + survivors
--   survivors   = listings first seen by D that are live now or were removed
--                 after D, minus anything gone in the window
--
-- Hook: finalize_cardtrader_daily_market_refresh runs it right after the
-- vacation reclassification, before the sold graph rebuild. Removals start
-- pending (093) and need three complete absences to count, so most are
-- reclassified before they could be projected; any observation that already
-- exists (backfill, a store whose ramp began before the window) is deleted.
--
-- One-time backfill: every removed_day since 2026-09-01, oldest first, then
-- the sold graph and price summary rebuild.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;
set local work_mem = '256MB';

-- The single-dump draft had no window parameter; never leave an overload.
drop function if exists public.cardtrader_reclassify_store_withdrawals(text, date, integer, numeric);

create or replace function public.cardtrader_reclassify_store_withdrawals(
  p_provider text default 'cardtrader',
  p_removed_day date default (current_date - 1),
  p_min_book integer default 500,
  p_min_share numeric default 0.8,
  p_window_days integer default 7
)
returns table(sellers integer, events integer, qty bigint)
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  v_provider text := coalesce(nullif(btrim(p_provider), ''), 'cardtrader');
  v_day date := coalesce(p_removed_day, current_date - 1);
  v_min_book integer := greatest(coalesce(p_min_book, 500), 1);
  v_min_share numeric := least(greatest(coalesce(p_min_share, 0.8), 0.01), 1);
  v_from date := coalesce(p_removed_day, current_date - 1)
                 - (greatest(coalesce(p_window_days, 7), 1) - 1);
begin
  perform set_config('statement_timeout', '0', true);

  drop table if exists store_withdrawn_sellers;
  create temporary table store_withdrawn_sellers (
    seller_account_id text primary key,
    vanished integer not null,
    book_before integer not null
  ) on commit drop;

  -- Candidates first (cheap, one window): enough vanished listings to reach
  -- the share on the smallest qualifying book. Survivors are then probed per
  -- seller through the seller indexes.
  insert into pg_temp.store_withdrawn_sellers (seller_account_id, vanished, book_before)
  select c.seller_account_id, c.vanished, c.gone + s.survivors
  from (
    select
      h.seller_account_id,
      count(distinct h.external_listing_id) filter (
        where h.archive_reason in ('inferred_sale', 'young_listing_removed', 'seller_store_withdrawn')
      )::integer as vanished,
      count(distinct h.external_listing_id)::integer as gone
    from public.cardtrader_market_listing_removed_history h
    where h.provider = v_provider
      and h.removed_day between v_from and v_day
      and h.seller_account_id <> ''
      and h.archive_reason <> 'quantity_decreased'
    group by h.seller_account_id
    having count(distinct h.external_listing_id) filter (
      where h.archive_reason in ('inferred_sale', 'young_listing_removed', 'seller_store_withdrawn')
    ) >= ceil(v_min_book * v_min_share)
  ) c
  cross join lateral (
    select count(*)::integer as survivors
    from (
      select live.external_listing_id
      from public.cardtrader_market_listing_snapshots live
      where live.provider = v_provider
        and live.seller_account_id = c.seller_account_id
        and (live.first_seen_at at time zone 'utc')::date <= v_day
      union
      select later.external_listing_id
      from public.cardtrader_market_listing_removed_history later
      where later.provider = v_provider
        and later.seller_account_id = c.seller_account_id
        and later.removed_day > v_day
        and (later.first_seen_at at time zone 'utc')::date <= v_day
      except
      select gone.external_listing_id
      from public.cardtrader_market_listing_removed_history gone
      where gone.provider = v_provider
        and gone.seller_account_id = c.seller_account_id
        and gone.removed_day between v_from and v_day
        and gone.archive_reason <> 'quantity_decreased'
    ) survivor_ids
  ) s
  where c.gone + s.survivors >= v_min_book
    and c.vanished >= v_min_share * (c.gone + s.survivors);

  delete from public.marketplace_price_observations o
  using public.cardtrader_market_listing_removed_history h
  join pg_temp.store_withdrawn_sellers w
    on w.seller_account_id = h.seller_account_id
  where o.source = 'cardtrader_removed_sale'
    and h.provider = v_provider
    and h.removed_day between v_from and v_day
    and h.archive_reason in ('inferred_sale', 'young_listing_removed')
    and o.source_item_id = h.provider || ':' || h.external_listing_id || ':' || h.removed_day::text || ':' || h.archive_reason;

  update public.cardtrader_market_listing_removed_history h
  set
    archive_reason = 'seller_store_withdrawn',
    archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedFrom', h.archive_reason,
      'reclassifiedBecause', 'seller_store_withdrawn_103',
      'storeWindowEnd', v_day,
      'storeVanished', w.vanished,
      'storeBookBefore', w.book_before
    )
  from pg_temp.store_withdrawn_sellers w
  where h.provider = v_provider
    and h.removed_day between v_from and v_day
    and h.archive_reason in ('inferred_sale', 'young_listing_removed')
    and h.seller_account_id = w.seller_account_id;

  return query
  select
    count(distinct w.seller_account_id)::integer,
    count(h.id)::integer,
    coalesce(sum(h.quantity), 0)::bigint
  from pg_temp.store_withdrawn_sellers w
  left join public.cardtrader_market_listing_removed_history h
    on h.provider = v_provider
   and h.removed_day between v_from and v_day
   and h.archive_reason = 'seller_store_withdrawn'
   and h.seller_account_id = w.seller_account_id;
end;
$$;

create or replace function public.finalize_cardtrader_daily_market_refresh(
  p_provider text default 'cardtrader'::text,
  p_removed_day date default (current_date - 1),
  p_imported_at timestamp with time zone default now()
)
returns table(cache_refreshed_count integer, analytics_count integer, price_summary_count integer)
language plpgsql
security definer
set search_path to 'public'
set statement_timeout to '0'
as $function$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_day date := coalesce(p_removed_day, current_date - 1);
begin
  perform set_config('statement_timeout', '0', true);

  select public.refresh_cardtrader_blueprint_listing_cache(v_provider, '[]'::jsonb, p_imported_at)
  into cache_refreshed_count;

  perform public.annotate_cardtrader_removed_sale_observations(v_day);
  perform public.cardtrader_reclassify_vacation_vanished_sellers(v_provider, v_day);
  -- 103: whole-store withdrawals (7-day window) are not sales.
  perform public.cardtrader_reclassify_store_withdrawals(v_provider, v_day);
  -- Full rebuild: corrections and delayed attribution can touch any day.
  perform public.refresh_cardtrader_sold_daily(null);

  select public.refresh_cardtrader_blueprint_daily_analytics(v_day)
  into analytics_count;

  select public.refresh_marketplace_blueprint_price_summary(null)
  into price_summary_count;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$function$;

-- ---------------------------------------------------------------------------
-- One-time (idempotent) backfill: every removed_day since the sold model's
-- first complete-book dumps, oldest first. Re-running finds nothing left.
-- cardtrader_blueprint_daily_analytics is not re-run: it rebuilds a day from
-- today's listing population, which would overwrite historical listed counts.
-- ---------------------------------------------------------------------------

do $$
declare
  d date;
  r record;
begin
  for d in
    select g::date from generate_series(date '2026-09-01', current_date - 1, interval '1 day') g
  loop
    select * into r from public.cardtrader_reclassify_store_withdrawals('cardtrader', d);
    if r.sellers > 0 then
      raise notice '103 backfill window ending %: % sellers, % listings, % copies', d, r.sellers, r.events, r.qty;
    end if;
  end loop;
end $$;

select public.refresh_cardtrader_sold_daily(null) as sold_daily_rows;
select public.refresh_marketplace_blueprint_price_summary(null) as price_summary_rows;

commit;
