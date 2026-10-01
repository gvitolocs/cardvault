-- 104: set-based survivors for cardtrader_reclassify_store_withdrawals (103).
--
-- Why (2026-09-30, right after applying 103): 103 probed each candidate
-- seller's survivors in a LATERAL subquery through the seller indexes. With
-- ~150 candidate stores per 7-day window that is random heap reads over the
-- 7 GB snapshot table: one nightly pass took 4m58s (the whole finalize was
-- ~78s before 103). Computing candidates once and joining survivors by hash
-- gives the identical seller set (window ending 2026-09-29: 41 sellers,
-- 0 rows differ) in ~4s. Same signature, same rule, same outputs; no
-- backfill needed.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

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
  perform set_config('work_mem', '256MB', true);

  drop table if exists store_withdrawal_candidates;
  create temporary table store_withdrawal_candidates (
    seller_account_id text primary key,
    vanished integer not null,
    gone integer not null
  ) on commit drop;

  drop table if exists store_withdrawn_sellers;
  create temporary table store_withdrawn_sellers (
    seller_account_id text primary key,
    vanished integer not null,
    book_before integer not null
  ) on commit drop;

  -- Candidates (one window): enough vanished listings to reach the share on
  -- the smallest qualifying book.
  insert into pg_temp.store_withdrawal_candidates (seller_account_id, vanished, gone)
  select
    h.seller_account_id,
    count(distinct h.external_listing_id) filter (
      where h.archive_reason in ('inferred_sale', 'young_listing_removed', 'seller_store_withdrawn')
    )::integer,
    count(distinct h.external_listing_id)::integer
  from public.cardtrader_market_listing_removed_history h
  where h.provider = v_provider
    and h.removed_day between v_from and v_day
    and h.seller_account_id <> ''
    and h.archive_reason <> 'quantity_decreased'
  group by h.seller_account_id
  having count(distinct h.external_listing_id) filter (
    where h.archive_reason in ('inferred_sale', 'young_listing_removed', 'seller_store_withdrawn')
  ) >= ceil(v_min_book * v_min_share);

  analyze pg_temp.store_withdrawal_candidates;

  -- Survivors for every candidate at once (hash joins, not per-seller probes).
  insert into pg_temp.store_withdrawn_sellers (seller_account_id, vanished, book_before)
  with gone_ids as (
    select distinct h.seller_account_id, h.external_listing_id
    from public.cardtrader_market_listing_removed_history h
    join pg_temp.store_withdrawal_candidates c using (seller_account_id)
    where h.provider = v_provider
      and h.removed_day between v_from and v_day
      and h.archive_reason <> 'quantity_decreased'
  ),
  survivor_ids as (
    select live.seller_account_id, live.external_listing_id
    from public.cardtrader_market_listing_snapshots live
    join pg_temp.store_withdrawal_candidates c using (seller_account_id)
    where live.provider = v_provider
      and (live.first_seen_at at time zone 'utc')::date <= v_day
    union
    select later.seller_account_id, later.external_listing_id
    from public.cardtrader_market_listing_removed_history later
    join pg_temp.store_withdrawal_candidates c using (seller_account_id)
    where later.provider = v_provider
      and later.removed_day > v_day
      and (later.first_seen_at at time zone 'utc')::date <= v_day
  ),
  survivor_counts as (
    select s.seller_account_id, count(*)::integer as survivors
    from survivor_ids s
    where not exists (
      select 1
      from gone_ids g
      where g.seller_account_id = s.seller_account_id
        and g.external_listing_id = s.external_listing_id
    )
    group by s.seller_account_id
  )
  select c.seller_account_id, c.vanished, c.gone + coalesce(n.survivors, 0)
  from pg_temp.store_withdrawal_candidates c
  left join survivor_counts n using (seller_account_id)
  where c.gone + coalesce(n.survivors, 0) >= v_min_book
    and c.vanished >= v_min_share * (c.gone + coalesce(n.survivors, 0));

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

commit;
