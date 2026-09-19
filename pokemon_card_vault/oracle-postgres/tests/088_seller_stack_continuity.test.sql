-- Behavior tests for 088_seller_stack_continuity.
-- Run against a THROWAWAY database restored from the production schema
-- (pg_dump --schema-only), never against production data:
--   createdb pokoin_pipeline_test
--   pg_dump --schema-only prod | psql pokoin_pipeline_test
--   psql pokoin_pipeline_test -v ON_ERROR_STOP=1 \
--     -f oracle-postgres/tests/088_seller_stack_continuity.test.sql
-- Every test RAISEs on failure; a clean run prints only T<n> ok lines.

\set ON_ERROR_STOP on
\set QUIET on

delete from public.cardtrader_market_listing_removed_history where blueprint_id between 987001 and 987099;
delete from public.cardtrader_market_listing_snapshots where blueprint_id between 987001 and 987099;
delete from public.marketplace_price_observations where blueprint_id between 987001 and 987099;

create or replace function pg_temp.t_arch(
  lid text, bp bigint, sid text, sname text, qty int, cond text, lang text,
  day date, reason text default 'inferred_sale', props jsonb default '{}'::jsonb
) returns void language sql as $fn$
  insert into public.cardtrader_market_listing_removed_history
    (provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
     quantity, condition, language, price, removed_day, archive_reason, status, properties, raw_metadata)
  values ('cardtrader', lid, bp, sid, sname, qty, cond, lang, 1.00, day, reason,
          case when reason = 'quantity_decreased' then 'confirmed' else 'provisional' end, props, '{}'::jsonb);
  insert into public.marketplace_price_observations (blueprint_id, source, source_item_id, quantity, price)
  values (bp, 'cardtrader_removed_sale', 'cardtrader:' || lid || ':' || day::text || ':' || reason, qty, 1.00);
$fn$;

create or replace function pg_temp.t_live(
  lid text, bp bigint, sid text, sname text, qty int, cond text, lang text,
  props jsonb default '{}'::jsonb
) returns void language sql as $fn$
  insert into public.cardtrader_market_listing_snapshots
    (provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
     quantity, condition, language, price, properties, raw_metadata)
  values ('cardtrader', lid, bp, sid, sname, qty, cond, lang, 1.00, props, '{}'::jsonb);
$fn$;

-- 987011 mirrors the Beedrill (389944) Sep-17 incident.
select pg_temp.t_arch('T451578836', 987011, '177836', 'Trading Card Buyer', 934, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T452947010', 987011, '177836', 'Trading Card Buyer', 940, 'Near Mint', 'en');
select pg_temp.t_arch('T450462999', 987011, '327498', 'TheSportsShaq', 7, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T452697860', 987011, '327498', 'TheSportsShaq', 7, 'Near Mint', 'en');
select pg_temp.t_arch('T427765316', 987011, '999001', 'Trainer Legacy LTD', 1, 'Near Mint', 'en', date '2026-09-17', 'quantity_decreased');
select pg_temp.t_arch('T450555101', 987011, '900100', 'GameNation', 4, 'Near Mint', 'en', date '2026-09-17');

-- non-continuity controls: different seller / blueprint / condition / language / grade
select pg_temp.t_arch('T60001', 987011, '900200', 'SellerA', 5, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T60002', 987011, '900299', 'SellerB', 50, 'Near Mint', 'en');
select pg_temp.t_arch('T60003', 987011, '900300', 'SellerC', 5, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T60004', 987012, '900300', 'SellerC', 50, 'Near Mint', 'en');
select pg_temp.t_arch('T60005', 987011, '900400', 'SellerD', 5, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T60006', 987011, '900400', 'SellerD', 50, 'Slightly Played', 'en');
select pg_temp.t_arch('T60007', 987011, '900500', 'SellerE', 5, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T60008', 987011, '900500', 'SellerE', 50, 'Near Mint', 'it');
select pg_temp.t_arch('T60009', 987011, '900600', 'SellerF', 5, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T60010', 987011, '900600', 'SellerF', 50, 'Near Mint', 'en', '{"graded":"true"}'::jsonb);

-- 987012 mirrors the second Sep-17 blueprint: partial continuity + stack allocation.
select pg_temp.t_arch('T436986126', 987012, '177836', 'Trading Card Buyer', 56, 'Near Mint', 'en', date '2026-09-17');
select pg_temp.t_live('T452943137', 987012, '177836', 'Trading Card Buyer', 53, 'Near Mint', 'en');
select pg_temp.t_arch('T436986208', 987012, '177836', 'Trading Card Buyer', 25, 'Moderately Played', 'en', date '2026-09-17');
select pg_temp.t_arch('T436986211', 987012, '177836', 'Trading Card Buyer', 1, 'Moderately Played', 'en', date '2026-09-17');
select pg_temp.t_live('T452943228', 987012, '177836', 'Trading Card Buyer', 25, 'Moderately Played', 'en');

-- Sep-11/Sep-12 cutover episode, outside the reconciliation range.
select pg_temp.t_arch('T70001', 987011, '177836', 'Trading Card Buyer', 99, 'Near Mint', 'en', date '2026-09-11');

select * from public.reconcile_cardtrader_seller_stack_continuity(
  'cardtrader', date '2026-09-15', date '2026-09-18');

\set QUIET off
\echo 'T1: rotated stack (934 -> 940) is not a sale'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T451578836'
                   and status = 'retracted' and archive_reason = 'listing_id_rotated') then
    raise exception 'T1: 934->940 rotation was not retracted';
  end if;
  if exists (select 1 from public.marketplace_price_observations
             where source_item_id like 'cardtrader:T451578836:%') then
    raise exception 'T1: retracted episode still has a price observation';
  end if;
end $$;

\set QUIET off
\echo 'T2: equal-quantity rotation (7 -> 7) is not a sale'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T450462999' and status = 'retracted') then
    raise exception 'T2: 7->7 rotation was not retracted';
  end if;
end $$;

\set QUIET off
\echo 'T3: quantity_decreased is never touched'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T427765316'
                   and archive_reason = 'quantity_decreased'
                   and status = 'confirmed' and quantity = 1) then
    raise exception 'T3: quantity_decreased episode was modified';
  end if;
  if not exists (select 1 from public.marketplace_price_observations
                 where source_item_id like 'cardtrader:T427765316:%') then
    raise exception 'T3: quantity_decreased observation was deleted';
  end if;
end $$;

\set QUIET off
\echo 'T4: genuinely absent stack stays finalizable (liveness)'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T450555101'
                   and status = 'provisional' and archive_reason = 'inferred_sale' and quantity = 4) then
    raise exception 'T4: absent stack was wrongly suppressed';
  end if;
end $$;

\set QUIET off
\echo 'T5: continuity never crosses seller, blueprint, condition, language or grade'
\set QUIET on
do $$
declare
  v text;
begin
  foreach v in array array['T60001','T60003','T60005','T60007','T60009'] loop
    if not exists (select 1 from public.cardtrader_market_listing_removed_history
                   where external_listing_id = v and status = 'provisional' and quantity = 5) then
      raise exception 'T5: % was incorrectly treated as continuity', v;
    end if;
  end loop;
end $$;

\set QUIET off
\echo 'T6: partial continuity (56 -> 53) keeps a provisional 3-unit residual'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T436986126'
                   and quantity = 3 and status = 'provisional' and archive_reason = 'inferred_sale') then
    raise exception 'T6: 56->53 residual is not a provisional 3-unit episode';
  end if;
  if not exists (select 1 from public.marketplace_price_observations
                 where source_item_id like 'cardtrader:T436986126:%' and quantity = 3) then
    raise exception 'T6: residual observation quantity was not reduced to 3';
  end if;
end $$;

\set QUIET off
\echo 'T7: successor units are allocated once across a stack, never double-claimed'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T436986208' and status = 'retracted') then
    raise exception 'T7: the 25-unit predecessor should consume the 25-unit successor';
  end if;
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T436986211'
                   and status = 'provisional' and quantity = 1) then
    raise exception 'T7: the 1-unit predecessor double-claimed the same successor units';
  end if;
end $$;

\set QUIET off
\echo 'T8: episodes outside the reconciliation range are untouched (Sep-11 cutover)'
\set QUIET on
do $$
begin
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T70001'
                   and status = 'provisional' and quantity = 99) then
    raise exception 'T8: an out-of-range episode was modified';
  end if;
end $$;

\set QUIET off
\echo 'T9: reconciliation is idempotent — a second pass credits nothing further'
\set QUIET on
do $$
declare
  r record;
begin
  select * into r from public.reconcile_cardtrader_seller_stack_continuity(
    'cardtrader', date '2026-09-15', date '2026-09-18');
  if r.retracted_rows <> 0 or r.reduced_rows <> 0 then
    raise exception 'T9: second pass changed % rows (retracted) / % rows (reduced)',
      r.retracted_rows, r.reduced_rows;
  end if;
  if not exists (select 1 from public.cardtrader_market_listing_removed_history
                 where external_listing_id = 'T436986126' and quantity = 3 and status = 'provisional') then
    raise exception 'T9: a second pass erased the genuine partial sale';
  end if;
end $$;

\set QUIET off
\echo 'T10: the incident blueprint keeps exactly its one legitimate episode'
\set QUIET on
do $$
begin
  if (select count(*) from public.cardtrader_market_listing_removed_history
      where blueprint_id = 987011 and removed_day = date '2026-09-17'
        and status <> 'retracted'
        and external_listing_id in ('T451578836','T450462999','T427765316')) <> 1 then
    raise exception 'T10: expected exactly the quantity_decreased episode to survive';
  end if;
end $$;

\set QUIET on
delete from public.cardtrader_market_listing_removed_history where blueprint_id between 987001 and 987099;
delete from public.cardtrader_market_listing_snapshots where blueprint_id between 987001 and 987099;
delete from public.marketplace_price_observations where blueprint_id between 987001 and 987099;
\set QUIET off
\echo 'all ok'
