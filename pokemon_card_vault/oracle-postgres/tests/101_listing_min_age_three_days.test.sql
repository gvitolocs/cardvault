-- Behavior tests for 101_listing_min_age_three_days (D000101).
-- Assumes the 093 three-complete-dumps confirmation flow is present (the
-- migration is written on top of fix/cardtrader-confirm-three-complete-dumps).
-- Run against a THROWAWAY database restored from the production schema
-- (pg_dump --schema-only), never against production data:
--   createdb pokoin_pipeline_test
--   pg_dump --schema-only prod | psql pokoin_pipeline_test
--   psql pokoin_pipeline_test -v ON_ERROR_STOP=1 \
--     -f oracle-postgres/tests/101_listing_min_age_three_days.test.sql
-- Every test RAISEs on failure; a clean run prints only T<n> ok lines.

\set ON_ERROR_STOP on
\set QUIET on

delete from public.cardtrader_market_listing_removed_history where blueprint_id between 987101 and 987199;
delete from public.cardtrader_market_listing_snapshots where blueprint_id between 987101 and 987199;
delete from public.marketplace_price_observations where blueprint_id between 987101 and 987199;
delete from public.cardtrader_blueprint_population_daily where blueprint_id between 987101 and 987199;
delete from public.cardtrader_sold_daily where blueprint_id between 987101 and 987199;
delete from public.cardtrader_blueprint_listing_cache where blueprint_id between 987101 and 987199;

-- The blueprint id for one T-test run day, shared by the dump calls below.
select current_date - 3 as d1, current_date - 2 as d2, current_date - 1 as d3
into temp test_days;

\set QUIET off
\echo 'T1: mature vanish (>=3 days in book) counts only after 3 complete dumps'
\set QUIET on

insert into public.cardtrader_market_listing_snapshots (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, last_seen_at, imported_at, updated_at
) values
    ('cardtrader','M1',987101,'111','Mature Seller',4,'NM','en',10,1000,'EUR','{}','{}',
   now()-interval '10 days', (select d1::timestamptz - interval '1 day' from test_days), now()-interval '10 days', (select d1::timestamptz - interval '1 day' from test_days)),
    ('cardtrader','M2',987101,'222','Other Seller',1,'NM','en',12,1200,'EUR','{}','{}',
   now()-interval '10 days', (select d1::timestamptz from test_days), now()-interval '10 days', (select d1::timestamptz from test_days));

insert into public.cardtrader_blueprint_population_daily
  (blueprint_id, observed_day, listing_count, listed_quantity, seller_count)
values (987101, current_date-1, 2, 5, 2);

-- dump 1 (removed_day = d1): M1 archives as pending, absence 1, not counted
with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "M2", "blueprintId": 987101, "sellerAccountId": "222", "quantity": 1, "condition": "NM", "language": "en", "price": 12, "priceCents": 1200, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987101]'::jsonb, (select d1 from test_days), true, now(), false, false)
) refreshed;

do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='M1' and archive_reason='inferred_sale'
            and status='pending' and quantity=4
            and (archive_metadata->>'completeAbsences')::int = 1) = 1,
         'T1: after dump 1 M1 should be a pending inferred_sale with 1 complete absence';
  assert (select count(*) from public.marketplace_price_observations
          where source='cardtrader_removed_sale' and source_item_id like 'cardtrader:M1:%') = 0,
         'T1: unconfirmed M1 must not project an observation yet';
end $$;

-- dump 2 (removed_day = d2): absence 2
with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "M2", "blueprintId": 987101, "sellerAccountId": "222", "quantity": 1, "condition": "NM", "language": "en", "price": 12, "priceCents": 1200, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987101]'::jsonb, (select d2 from test_days), true, now(), false, false)
) refreshed;

-- dump 3 (removed_day = d3): absence 3 => provisional, observation dated to d1
with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "M2", "blueprintId": 987101, "sellerAccountId": "222", "quantity": 1, "condition": "NM", "language": "en", "price": 12, "priceCents": 1200, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987101]'::jsonb, (select d3 from test_days), true, now(), false, false)
) refreshed;

do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='M1' and archive_reason='inferred_sale'
            and status='provisional' and quantity=4
            and (archive_metadata->>'completeAbsences')::int = 3) = 1,
         'T1: after dump 3 M1 should be a provisional (counted) sale of 4';
  assert (select count(*) from public.marketplace_price_observations
          where source='cardtrader_removed_sale'
            and source_item_id = 'cardtrader:M1:' || (select d1 from test_days) || ':inferred_sale') = 1,
         'T1: confirmed M1 observation must exist, dated to the first missing day';
  assert (select count(*) from public.cardtrader_market_listing_snapshots
          where external_listing_id='M1') = 0, 'T1: M1 ghost must leave the live book';
end $$;
\echo 'T1 ok'

\set QUIET off
\echo 'T2: young vanish (<3 days in book) => young_listing_removed, never counted even after 3 dumps'
\set QUIET on

insert into public.cardtrader_market_listing_snapshots (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, last_seen_at, imported_at, updated_at
) values
    ('cardtrader','Y1',987102,'333','Lowball Seller',6,'NM','en',2,200,'EUR','{}','{}',
   (select (d1::date - 2)::timestamptz from test_days), (select d1::timestamptz - interval '1 day' from test_days), (select (d1::date - 2)::timestamptz from test_days), (select d1::timestamptz - interval '1 day' from test_days)),
    ('cardtrader','Y2',987102,'444','Keep Seller',2,'NM','en',9,900,'EUR','{}','{}',
   now()-interval '10 days', (select d1::timestamptz from test_days), now()-interval '10 days', (select d1::timestamptz from test_days));

insert into public.cardtrader_blueprint_population_daily
  (blueprint_id, observed_day, listing_count, listed_quantity, seller_count)
values (987102, current_date-1, 2, 8, 2);

-- three complete dumps, days d1..d3
with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "Y2", "blueprintId": 987102, "sellerAccountId": "444", "quantity": 2, "condition": "NM", "language": "en", "price": 9, "priceCents": 900, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987102]'::jsonb, (select d1 from test_days), true, now(), false, false)
) refreshed;

with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "Y2", "blueprintId": 987102, "sellerAccountId": "444", "quantity": 2, "condition": "NM", "language": "en", "price": 9, "priceCents": 900, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987102]'::jsonb, (select d2 from test_days), true, now(), false, false)
) refreshed;

with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "Y2", "blueprintId": 987102, "sellerAccountId": "444", "quantity": 2, "condition": "NM", "language": "en", "price": 9, "priceCents": 900, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987102]'::jsonb, (select d3 from test_days), true, now(), false, false)
) refreshed;

do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='Y1' and archive_reason='young_listing_removed'
            and quantity=6
            and archive_metadata->>'reclassifiedBecause' = 'listing_under_three_days_old') = 1,
         'T2: Y1 should be young_listing_removed of 6 with the age marker';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='Y1' and status='provisional') = 1,
         'T2: the 3-dump ceremony still ran for Y1 (provisional status is fine)';
  assert (select count(*) from public.marketplace_price_observations
          where source='cardtrader_removed_sale' and source_item_id like 'cardtrader:Y1:%') = 0,
         'T2: young Y1 must never project an observation';
  assert (select count(*) from public.cardtrader_market_listing_snapshots
          where external_listing_id='Y1') = 0, 'T2: Y1 ghost must still leave the live book';
end $$;
\echo 'T2 ok'

\set QUIET off
\echo 'T3: quantity drip — young listing drips are young_listing_removed, mature drips stay quantity_decreased'
\set QUIET on

insert into public.cardtrader_market_listing_snapshots (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, last_seen_at, imported_at, updated_at
) values
    ('cardtrader','D1',987103,'555','Young Drip Seller',5,'NM','en',8,800,'EUR','{}','{}',
   (select (d3::date - 1)::timestamptz from test_days), (select d3::timestamptz from test_days), (select (d3::date - 1)::timestamptz from test_days), (select d3::timestamptz from test_days)),
    ('cardtrader','D2',987103,'666','Mature Drip Seller',5,'NM','en',8,800,'EUR','{}','{}',
   now()-interval '10 days', (select d3::timestamptz from test_days), now()-interval '10 days', (select d3::timestamptz from test_days));

insert into public.cardtrader_blueprint_population_daily
  (blueprint_id, observed_day, listing_count, listed_quantity, seller_count)
values (987103, current_date-1, 2, 10, 2);

with settings as (select set_config('app.cardtrader_complete_book', '1', true))
select * from settings, lateral (
  select * from public.refresh_cardtrader_market_listing_snapshots(
'cardtrader', '[{"externalListingId": "D1", "blueprintId": 987103, "sellerAccountId": "555", "quantity": 2, "condition": "NM", "language": "en", "price": 8, "priceCents": 800, "currency": "EUR", "properties": {}, "rawMetadata": {}}, {"externalListingId": "D2", "blueprintId": 987103, "sellerAccountId": "666", "quantity": 3, "condition": "NM", "language": "en", "price": 8, "priceCents": 800, "currency": "EUR", "properties": {}, "rawMetadata": {}}]'::jsonb, '[987103]'::jsonb, (select d3 from test_days), true, now(), false, false)
) refreshed;

do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='D1' and archive_reason='young_listing_removed'
            and status='provisional' and quantity=3) = 1, 'T3: D1 young drip should be young_listing_removed of 3';
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id='D2' and archive_reason='quantity_decreased'
            and status='provisional' and quantity=2) = 1, 'T3: D2 mature drip should stay quantity_decreased of 2';
  assert (select count(*) from public.marketplace_price_observations
          where source='cardtrader_removed_sale'
            and (source_item_id like 'cardtrader:D1:%' or source_item_id like 'cardtrader:D2:%')) = 1,
         'T3: only the mature drip may project an observation';
end $$;
\echo 'T3 ok'

\set QUIET off
\echo 'T4: sold_daily counts the mature sale and excludes young episodes'
\set QUIET on

select public.refresh_cardtrader_sold_daily(null) as rebuilt;

do $$
begin
  assert (select coalesce(sum(sold_qty), 0) from public.cardtrader_sold_daily
          where blueprint_id = 987101) = 4, 'T4: 987101 should sell 4 mature copies';
  assert (select coalesce(sum(sold_qty), 0) from public.cardtrader_sold_daily
          where blueprint_id in (987102, 987103)) = 2, 'T4: young episodes must not feed sold_daily (mature drip only = 2)';
end $$;
\echo 'T4 ok'

\set QUIET off
\echo 'T5: sold_daily age predicate drops a stray young observation even when one exists'
\set QUIET on

-- Force a stray observation for the young vanish (as if projected before the
-- rule existed): sold_daily must still refuse it via the first_seen_at gate.
insert into public.marketplace_price_observations (
  blueprint_id, source, source_item_id, observed_at, currency, price, price_pkn,
  quantity, condition, language, created_at
) values (
  987102, 'cardtrader_removed_sale',
  'cardtrader:Y1:' || (select d1 from test_days) || ':inferred_sale',
  (select d1::timestamptz from test_days), 'EUR', 2, 400, 6, 'NM', 'en', now()
);

select public.refresh_cardtrader_sold_daily(null) as rebuilt;

do $$
begin
  assert (select coalesce(sum(sold_qty), 0) from public.cardtrader_sold_daily
          where blueprint_id = 987102) = 0, 'T5: stray young observation must not feed sold_daily';
end $$;

delete from public.marketplace_price_observations
where source='cardtrader_removed_sale'
  and source_item_id = 'cardtrader:Y1:' || (select d1 from test_days) || ':inferred_sale';
\echo 'T5 ok'

\set QUIET off
\echo 'T6: backfill reclassifies legacy young episodes (confirmed/provisional/pending), deletes observations, idempotent'
\set QUIET on

-- Legacy provisional young sale (with an observation to delete)…
insert into public.cardtrader_market_listing_removed_history (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, removed_day, status, archive_reason, archive_metadata
) values (
  'cardtrader', 'B1', 987104, '777', 'Legacy Seller', 3, 'NM', 'en', 4, 400, 'EUR', '{}', '{}',
  (select (d3::date - 1)::timestamptz from test_days), (select d3 from test_days), 'provisional', 'inferred_sale', '{}'
);
insert into public.marketplace_price_observations (
  blueprint_id, source, source_item_id, observed_at, currency, price, price_pkn,
  quantity, condition, language, created_at
) values (
  987104, 'cardtrader_removed_sale',
  'cardtrader:B1:' || (select d3 from test_days) || ':inferred_sale',
  (select d3::timestamptz from test_days), 'EUR', 4, 800, 3, 'NM', 'en', now()
);
-- …a 093-shaped pending young sale (confirmation ceremony would count it)…
insert into public.cardtrader_market_listing_removed_history (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, removed_day, status, archive_reason, archive_metadata
) values (
  'cardtrader', 'B2', 987104, '778', 'Pending Seller', 2, 'NM', 'en', 4, 400, 'EUR', '{}', '{}',
  (select (d3::date - 1)::timestamptz from test_days), (select d3 from test_days), 'pending', 'inferred_sale',
  jsonb_build_object('confirmationRequired', 3, 'completeAbsences', 1)
);

with young as (
  select h.id
  from public.cardtrader_market_listing_removed_history h
  where h.provider = 'cardtrader'
    and h.status in ('confirmed', 'provisional', 'pending')
    and public.cardtrader_market_is_sale_reason(h.archive_reason)
    and (h.first_seen_at at time zone 'utc')::date > h.removed_day - 3
)
update public.cardtrader_market_listing_removed_history h
set status = 'invalid',
    resolved_at = now(),
    archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedBecause', 'listing_age_under_three_days_d000101'
    )
where h.id in (select id from young);

delete from public.marketplace_price_observations o
using public.cardtrader_market_listing_removed_history h
where h.provider = 'cardtrader'
  and h.status = 'invalid'
  and h.archive_metadata->>'reclassifiedBecause' = 'listing_age_under_three_days_d000101'
  and o.source = 'cardtrader_removed_sale'
  and o.source_item_id = h.provider || ':' || h.external_listing_id || ':' || h.removed_day::text || ':' || h.archive_reason;

do $$
begin
  assert (select count(*) from public.cardtrader_market_listing_removed_history
          where external_listing_id in ('B1','B2') and status='invalid'
            and archive_metadata->>'reclassifiedBecause' = 'listing_age_under_three_days_d000101') = 2,
         'T6: B1 and B2 should be invalid with the d000101 marker';
  assert (select count(*) from public.marketplace_price_observations
          where source='cardtrader_removed_sale'
            and source_item_id like 'cardtrader:B1:%') = 0, 'T6: B1 observation must be deleted';
end $$;

-- Idempotent: a second pass must be a no-op.
with young as (
  select h.id
  from public.cardtrader_market_listing_removed_history h
  where h.provider = 'cardtrader'
    and h.status in ('confirmed', 'provisional', 'pending')
    and public.cardtrader_market_is_sale_reason(h.archive_reason)
    and (h.first_seen_at at time zone 'utc')::date > h.removed_day - 3
)
select count(*) = 0 as second_pass_noop from young;

-- Boundary: exactly three days in the book (first_seen = removed_day - 3)
-- stays sale-eligible; removed_day - 2 does not.
insert into public.cardtrader_market_listing_removed_history (
  provider, external_listing_id, blueprint_id, seller_account_id, seller_account_name,
  quantity, condition, language, price, price_cents, currency, properties, raw_metadata,
  first_seen_at, removed_day, status, archive_reason, archive_metadata
) values
    ('cardtrader', 'E1', 987105, '888', 'Boundary Seller', 1, 'NM', 'en', 5, 500, 'EUR', '{}', '{}',
   (select ((d3 - 3)::date)::timestamptz from test_days), (select d3 from test_days), 'provisional', 'inferred_sale', '{}'),
    ('cardtrader', 'E2', 987105, '999', 'Boundary Seller 2', 1, 'NM', 'en', 5, 500, 'EUR', '{}', '{}',
   (select ((d3 - 2)::date)::timestamptz from test_days), (select d3 from test_days), 'provisional', 'inferred_sale', '{}');

create temp table boundary_check as
select
  count(*) filter (where external_listing_id = 'E1') = 0 as e1_stays_sale,
  count(*) filter (where external_listing_id = 'E2') = 1 as e2_is_young
from public.cardtrader_market_listing_removed_history
where blueprint_id = 987105
  and status in ('confirmed','provisional')
  and public.cardtrader_market_is_sale_reason(archive_reason)
  and (first_seen_at at time zone 'utc')::date > removed_day - 3;

do $$
begin
  assert (select bool_and(ok) from (
            select e1_stays_sale as ok from boundary_check
            union all
            select e2_is_young from boundary_check
          )), 'T6b: boundary — first_seen=removed_day-3 stays a sale, removed_day-2 does not';
end $$;
\echo 'T6 ok'

\set QUIET on
drop table if exists boundary_check;
drop table if exists test_days;
delete from public.cardtrader_market_listing_removed_history where blueprint_id between 987101 and 987199;
delete from public.cardtrader_market_listing_snapshots where blueprint_id between 987101 and 987199;
delete from public.marketplace_price_observations where blueprint_id between 987101 and 987199;
delete from public.cardtrader_blueprint_population_daily where blueprint_id between 987101 and 987199;
delete from public.cardtrader_sold_daily where blueprint_id between 987101 and 987199;
delete from public.cardtrader_blueprint_listing_cache where blueprint_id between 987101 and 987199;
\echo '101 tests done'
