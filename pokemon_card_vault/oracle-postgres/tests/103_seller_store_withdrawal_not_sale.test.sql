-- Behavior tests for 103_seller_store_withdrawal_not_sale.
-- Run against a THROWAWAY database restored from the production schema
-- (pg_dump --schema-only) with 103 applied, never against production data:
--   createdb pokoin_pipeline_test
--   pg_dump --schema-only prod | psql pokoin_pipeline_test
--   psql pokoin_pipeline_test -f oracle-postgres/schema/103_seller_store_withdrawal_not_sale.sql
--   psql pokoin_pipeline_test -v ON_ERROR_STOP=1 \
--     -f oracle-postgres/tests/103_seller_store_withdrawal_not_sale.test.sql
-- Every test RAISEs on failure; a clean run prints only T<n> ok lines.
-- Sellers 9103xx, blueprints 987301..987399, listing ids W103-*.

\set ON_ERROR_STOP on
\set QUIET on

delete from public.cardtrader_market_listing_removed_history where external_listing_id like 'W103-%';
delete from public.cardtrader_market_listing_snapshots where external_listing_id like 'W103-%';
delete from public.marketplace_price_observations where source_item_id like 'cardtrader:W103-%';
delete from public.cardtrader_sold_daily where blueprint_id between 987301 and 987399;

select current_date - 5 as d into temp test_day;

-- History rows: seller, prefix, count, removed_day, reason, blueprint.
create or replace function pg_temp.seed_removed(
  p_seller text, p_prefix text, p_n integer, p_day date, p_reason text,
  p_blueprint bigint, p_status text default 'provisional'
) returns void language sql as $$
  insert into public.cardtrader_market_listing_removed_history (
    provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
    quantity, condition, language, price, price_cents, currency,
    first_seen_at, last_seen_at, removed_day, archive_reason, status, archive_metadata
  )
  select 'cardtrader', 'W103-' || p_prefix || '-' || g, p_blueprint, p_seller, 'Seller ' || p_seller,
         2, 'NM', 'en', 1.50, 150, 'EUR',
         p_day::timestamptz - interval '20 days', p_day::timestamptz, p_day, p_reason, p_status,
         '{}'::jsonb
  from generate_series(1, p_n) g;
$$;

create or replace function pg_temp.seed_live(
  p_seller text, p_prefix text, p_n integer, p_first_seen timestamptz
) returns void language sql as $$
  insert into public.cardtrader_market_listing_snapshots (
    provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
    quantity, condition, language, price, price_cents, currency,
    first_seen_at, last_seen_at, imported_at, updated_at
  )
  select 'cardtrader', 'W103-' || p_prefix || '-' || g, 987399, p_seller, 'Seller ' || p_seller,
         1, 'NM', 'en', 1.50, 150, 'EUR',
         p_first_seen, now(), now(), now()
  from generate_series(1, p_n) g;
$$;

-- Seller A: book 600, 500 vanish on d (83%) => withdrawn.
--   450 inferred_sale on blueprint 987301 (with observations), 50 young,
--   one same-id quantity drip that must stay, 100 still live.
select pg_temp.seed_removed('910301', 'A', 450, (select d from test_day), 'inferred_sale', 987301);
select pg_temp.seed_removed('910301', 'AY', 50, (select d from test_day), 'young_listing_removed', 987301, 'pending');
select pg_temp.seed_removed('910301', 'AQ', 1, (select d from test_day), 'quantity_decreased', 987302);
select pg_temp.seed_live('910301', 'AL', 100, (select d from test_day)::timestamptz - interval '20 days');
-- the drip's listing is still live
select pg_temp.seed_live('910301', 'AQ', 1, (select d from test_day)::timestamptz - interval '20 days');

insert into public.marketplace_price_observations (
  blueprint_id, source, source_item_id, observed_at, currency, price, price_pkn,
  quantity, condition, language
)
select h.blueprint_id, 'cardtrader_removed_sale',
       'cardtrader:' || h.external_listing_id || ':' || h.removed_day || ':' || h.archive_reason,
       h.removed_day::timestamptz, 'EUR', 1.50, 300, h.quantity, 'NM', 'EN'
from public.cardtrader_market_listing_removed_history h
where h.seller_account_id = '910301' and h.archive_reason in ('inferred_sale', 'quantity_decreased');

-- Seller B: small shop, book 450, loses all 450 => not withdrawn (< 500 book).
select pg_temp.seed_removed('910302', 'B', 450, (select d from test_day), 'inferred_sale', 987303);

-- Seller C: book 1000, loses 700 (70%) => not withdrawn.
select pg_temp.seed_removed('910303', 'C', 700, (select d from test_day), 'inferred_sale', 987304);
select pg_temp.seed_live('910303', 'CL', 300, (select d from test_day)::timestamptz - interval '20 days');

-- Seller D: 520 vanish on d, 0 live, but 200 listings present on d were
-- removed the next day => book 720, share 72% => not withdrawn.
select pg_temp.seed_removed('910304', 'D', 520, (select d from test_day), 'inferred_sale', 987305);
select pg_temp.seed_removed('910304', 'DL', 200, (select d + 1 from test_day), 'inferred_sale', 987305);

-- Seller E: 500 vanish, 400 live listings first seen AFTER d (new stock) do
-- not count as survivors => book 500, 100% => withdrawn.
select pg_temp.seed_removed('910305', 'E', 500, (select d from test_day), 'inferred_sale', 987306);
select pg_temp.seed_live('910305', 'EL', 400, (select d + 2 from test_day)::timestamptz);

select public.refresh_cardtrader_sold_daily(null);

\set QUIET off
\echo 'T0: before 103 runs, seller A''s vanishings are in the sold graph'
\set QUIET on
do $$
begin
  assert (select coalesce(sum(sold_qty), 0) from public.cardtrader_sold_daily where blueprint_id = 987301) = 900,
         'T0: seeded sold graph should hold 450 x 2 copies for 987301';
end $$;
\echo 'T0 ok'

create temp table t_run1 as
select * from public.cardtrader_reclassify_store_withdrawals('cardtrader', (select d from test_day));

\set QUIET off
\echo 'T1: 500+ book losing >= 80% is a store withdrawal, inferred_sale and young both reclassified'
\set QUIET on
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910301' and archive_reason = 'seller_store_withdrawn') = 500,
         'T1: all 500 seller-A vanishings should be seller_store_withdrawn';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910301' and archive_reason = 'seller_store_withdrawn'
            and archive_metadata->>'reclassifiedFrom' = 'young_listing_removed') = 50,
         'T1: young rows keep reclassifiedFrom=young_listing_removed';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910301' and archive_reason = 'seller_store_withdrawn'
            and (archive_metadata->>'storeBookBefore')::int = 601
            and (archive_metadata->>'storeVanished')::int = 500) = 500,
         'T1: metadata records book 601 (500 vanished + 101 live, the dripping listing included) and 500 vanished';
end $$;
\echo 'T1 ok'

\set QUIET off
\echo 'T2: withdrawn observations are deleted and the sold graph drops them; the drip stays'
\set QUIET on
select public.refresh_cardtrader_sold_daily(null);
do $$
begin
  assert (select count(*) from public.marketplace_price_observations
          where source_item_id like 'cardtrader:W103-A-%') = 0,
         'T2: seller A inferred_sale observations must be deleted';
  assert (select count(*) from public.cardtrader_sold_daily where blueprint_id = 987301) = 0,
         'T2: 987301 sold graph must be empty after reclassification';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910301' and archive_reason = 'quantity_decreased') = 1,
         'T2: the same-id quantity drip must stay quantity_decreased';
  assert (select count(*) from public.marketplace_price_observations
          where source_item_id like 'cardtrader:W103-AQ-%') = 1,
         'T2: the drip observation must stay';
end $$;
\echo 'T2 ok'

\set QUIET off
\echo 'T3: both thresholds must hold (small shop 100%, big shop 70%, later-removed survivors)'
\set QUIET on
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id in ('910302', '910303', '910304')
            and archive_reason = 'seller_store_withdrawn') = 0,
         'T3: sellers B (book 450), C (70%), D (72% with next-day survivors) are not withdrawals';
end $$;
\echo 'T3 ok'

\set QUIET off
\echo 'T4: listings first seen after the day are not survivors'
\set QUIET on
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910305' and archive_reason = 'seller_store_withdrawn') = 500,
         'T4: seller E new stock posted after d must not dilute the share';
  assert (select sellers from t_run1) = 2,
         'T4: run 1 reports two withdrawn sellers (A and E)';
end $$;
\echo 'T4 ok'

\set QUIET off
\echo 'T5: idempotent, and finalize runs the pass'
\set QUIET on
select public.cardtrader_reclassify_store_withdrawals('cardtrader', current_date - 5);
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id like 'W103-%' and archive_reason = 'seller_store_withdrawn') = 1000,
         'T5: a second run changes nothing (A 500 + E 500 withdrawn)';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id in ('910302', '910303', '910304')
            and archive_reason = 'inferred_sale') = 450 + 700 + 720,
         'T5: sellers below the thresholds keep their inferred_sale rows';
  assert position('cardtrader_reclassify_store_withdrawals'
                  in pg_get_functiondef('public.finalize_cardtrader_daily_market_refresh(text,date,timestamptz)'::regprocedure)) > 0,
         'T5: finalize must call the store-withdrawal pass';
  assert not public.cardtrader_market_is_sale_reason('seller_store_withdrawn'),
         'T5: seller_store_withdrawn is not a sale reason';
end $$;
\echo 'T5 ok'

-- Window cases on their own days (d-20.. so they never touch A..E's window).
select current_date - 20 as w into temp window_day;

-- Seller F winds down over two dumps: 300 on w-3, 300 on w, 100 still live.
-- One dump alone is 300 (below the 400 candidate floor); the window is
-- 600 of 700 = 86%.
select pg_temp.seed_removed('910306', 'F1', 300, (select w - 3 from window_day), 'inferred_sale', 987307);
select pg_temp.seed_removed('910306', 'F2', 300, (select w from window_day), 'inferred_sale', 987307);
select pg_temp.seed_live('910306', 'FL', 100, (select w from window_day)::timestamptz - interval '20 days');

-- Seller G: 500 on w (with 100 more present that day), then those last 100
-- vanish on w+2. The second pass must still see G as withdrawn because its
-- earlier rows are already seller_store_withdrawn.
select pg_temp.seed_removed('910307', 'G1', 500, (select w from window_day), 'inferred_sale', 987308);
select pg_temp.seed_removed('910307', 'G2', 100, (select w + 2 from window_day), 'inferred_sale', 987308);

select public.cardtrader_reclassify_store_withdrawals('cardtrader', (select w from window_day));

\set QUIET off
\echo 'T6: a store that winds down over several dumps inside 7 days is one withdrawal'
\set QUIET on
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910306' and archive_reason = 'seller_store_withdrawn') = 600,
         'T6: both of seller F''s dumps (w-3 and w) are reclassified';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910307' and archive_reason = 'seller_store_withdrawn') = 500,
         'T6: seller G''s w rows are reclassified; w+2 is outside this window';
end $$;
\echo 'T6 ok'

select public.cardtrader_reclassify_store_withdrawals('cardtrader', (select w + 2 from window_day));

\set QUIET off
\echo 'T7: a flagged store keeps qualifying, so its later vanishings are not sales either'
\set QUIET on
do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where seller_account_id = '910307' and archive_reason = 'seller_store_withdrawn') = 600,
         'T7: seller G''s w+2 tail is reclassified too';
end $$;
\echo 'T7 ok'

delete from public.cardtrader_market_listing_removed_history where external_listing_id like 'W103-%';
delete from public.cardtrader_market_listing_snapshots where external_listing_id like 'W103-%';
delete from public.marketplace_price_observations where source_item_id like 'cardtrader:W103-%';
delete from public.cardtrader_sold_daily where blueprint_id between 987301 and 987399;
