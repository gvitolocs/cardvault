-- 102: set-based rewrite of refresh_cardtrader_sold_daily (follows D000101's
-- 087+age body, same output semantics, radically cheaper plan).
--
-- Why (deploy 2026-09-30): the 087-shaped body groups on jsonb facet helper
-- calls and carries the once_sold LEFT JOIN subquery. Measured on the nezopt
-- NVMe writer: each piece alone is fast (once_sold aggregate 0.45s, grouping
-- 2.7s, snapshot probes 0.6s), but the combined INSERT..SELECT thrashed for
-- 1-2h and spilled GBs of temp at default work_mem — every nightly
-- finalize_full rebuild would grind the same way. This body:
--   * computes the facet keys once per matched row in a CTE, then groups on
--     plain columns (hashable, no per-row jsonb re-evaluation at group time);
--   * keeps the once_sold "single observation day" rule as a precomputed CTE
--     and the live-listing backstop as an indexed NOT EXISTS probe;
--   * pins work_mem for the rebuild so the per-group sorts never spill.
-- Output semantics are byte-for-byte the 101 rules: source ids
-- cardtrader:{listing}:{day}:{inferred_sale|quantity_decreased}, status
-- confirmed|provisional, listing age >= 3 days, quantity_decreased always
-- eligible, inferred_sale only when the listing has exactly one observation
-- day and is no longer live in the book.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

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
  perform set_config('work_mem', '256MB', true);

  if target_day is not null then
    delete from public.cardtrader_sold_daily
    where observed_day = target_day;
  else
    -- DELETE, not TRUNCATE: a full rebuild must not hold ACCESS EXCLUSIVE
    -- over writer-side readers for the whole rebuild.
    delete from public.cardtrader_sold_daily;
  end if;

  with once_sold as materialized (
    select split_part(obs.source_item_id, ':', 2) as listing_id
    from public.marketplace_price_observations obs
    where obs.source = 'cardtrader_removed_sale'
      and obs.source_item_id like 'cardtrader:%'
      and split_part(obs.source_item_id, ':', 4) is distinct from 'quantity_decreased'
    group by 1
    having count(distinct (obs.observed_at at time zone 'utc')::date) = 1
  ),
  matched as materialized (
    select
      obs.blueprint_id,
      (obs.observed_at at time zone 'utc')::date as observed_day,
      public.cardtrader_sold_condition(obs.condition) as condition,
      public.cardtrader_sold_language(obs.language) as language,
      public.cardtrader_listing_is_reverse(
        coalesce(history.properties, '{}'::jsonb),
        obs.reverse,
        obs.foil_state
      ) as is_reverse,
      public.cardtrader_listing_is_first_edition(
        coalesce(history.properties, '{}'::jsonb),
        obs.first_edition
      ) as is_first_edition,
      obs.graded,
      nullif(obs.metadata->>'sellerComment', '') as seller_comment,
      obs.price_pkn,
      obs.quantity,
      split_part(obs.source_item_id, ':', 4) = 'quantity_decreased' as is_drip,
      split_part(obs.source_item_id, ':', 2) as listing_id
    from public.marketplace_price_observations obs
    left join public.cardtrader_market_listing_removed_history history
      on history.provider = split_part(obs.source_item_id, ':', 1)
     and history.external_listing_id = split_part(obs.source_item_id, ':', 2)
     and history.removed_day = (split_part(obs.source_item_id, ':', 3))::date
     and history.archive_reason = split_part(obs.source_item_id, ':', 4)
    where obs.source = 'cardtrader_removed_sale'
      and obs.source_item_id like 'cardtrader:%'
      and split_part(obs.source_item_id, ':', 4) in ('inferred_sale', 'quantity_decreased')
      and coalesce(history.status, 'confirmed') in ('confirmed', 'provisional')
      and (history.first_seen_at at time zone 'utc')::date
          <= (obs.observed_at at time zone 'utc')::date - 3
      and obs.price_pkn > 0
      and obs.blueprint_id is not null
      and (target_day is null or (obs.observed_at at time zone 'utc')::date = target_day)
      and public.cardtrader_sold_condition(obs.condition) is not null
      and public.cardtrader_sold_language(obs.language) is not null
  ),
  eligible as (
    select m.*
    from matched m
    left join once_sold o on o.listing_id = m.listing_id
    where m.is_drip
      or (
        o.listing_id is not null
        and not exists (
          select 1
          from public.cardtrader_market_listing_snapshots live
          where live.provider = 'cardtrader'
            and live.external_listing_id = m.listing_id
        )
      )
  )
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
    blueprint_id,
    observed_day,
    condition,
    language,
    is_reverse,
    is_first_edition,
    graded,
    percentile_cont(0.5) within group (order by price_pkn) as median_pkn,
    min(price_pkn) as min_pkn,
    max(price_pkn) as max_pkn,
    coalesce(sum(quantity), 0)::integer as sold_qty,
    count(*)::integer as listings,
    count(*)::integer as sample_count,
    case
      when graded then coalesce(
        array_remove(array_agg(distinct seller_comment), null),
        '{}'::text[]
      )
      else '{}'::text[]
    end as graded_comments,
    now()
  from eligible
  group by
    blueprint_id,
    observed_day,
    condition,
    language,
    is_reverse,
    is_first_edition,
    graded;

  get diagnostics refreshed_count = row_count;
  return coalesce(refreshed_count, 0);
end;
$$;

select public.refresh_cardtrader_sold_daily(null) as sold_daily_rows;
select public.refresh_marketplace_blueprint_price_summary(null) as price_summary_rows;

commit;
