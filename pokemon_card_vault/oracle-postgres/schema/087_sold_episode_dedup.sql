-- Episode dedup for the corrected sold pipeline (D000070).
--
-- A listing id with MULTIPLE inferred_sale episodes necessarily reappeared
-- between them (the later episode could not exist otherwise): every episode
-- except the terminal one is a temporary disappearance, not a sale. This
-- lets the once-sold backstop (one distinct observation day per listing id)
-- keep protecting against flicker without suppressing the terminal,
-- genuine sale (Rapidash 115974: 375012097 vanished 2026-09-04, returned,
-- vanished for good 2026-09-11 — the 09-04 episode is invalidated here).
-- Idempotent: already-invalidated earlier episodes never match again.
--
-- Also: refresh_cardtrader_sold_daily's full rebuild deletes rows instead of
-- TRUNCATE so writer-side readers are not blocked for the rebuild duration.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;
set local work_mem = '512MB';

with episodes as (
  select h.id,
         lead(h.removed_day) over (partition by h.external_listing_id order by h.removed_day) as next_episode_day
  from public.cardtrader_market_listing_removed_history h
  where h.provider = 'cardtrader'
    and h.status = 'confirmed'
    and h.archive_reason = 'inferred_sale'
)
update public.cardtrader_market_listing_removed_history h
set status = 'invalid',
    resolved_at = now(),
    archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedBecause', 'earlier_episode_reappeared_d000070'
    )
where h.id in (select id from episodes where next_episode_day is not null);

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
    -- DELETE, not TRUNCATE: a full rebuild must not hold ACCESS EXCLUSIVE
    -- over writer-side readers for the whole rebuild.
    delete from public.cardtrader_sold_daily;
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

select public.refresh_cardtrader_sold_daily(null) as sold_daily_rows;
select public.refresh_marketplace_blueprint_price_summary(null) as price_summary_rows;

commit;
