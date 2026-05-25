# Oracle Marketplace Postgres

This directory contains the repeatable schema and migration tooling for the
Oracle-backed marketplace/catalog/search database. Oracle Postgres is the source
of truth for marketplace projections; Supabase is retained for forum tables only.

## Environment

Set these locally or in Vercel/CI before running migration commands:

```bash
export SUPABASE_DB_URL='postgresql://...'
export MARKETPLACE_DATABASE_URL='postgresql://pokoin_marketplace:...@peer4-host:5432/pokoin_marketplace'
export MARKETPLACE_DATABASE_SSL_VERIFY=0
```

`SUPABASE_DB_URL` is only used by the copy step. `MARKETPLACE_DATABASE_URL` is
used by migration, verification, listing storage, and the Vercel marketplace
APIs. The migration script also auto-loads `.env.local`, so local commands can
usually run without manual exports.

## Commands

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js copy
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

Or run the complete flow:

```bash
node scripts/oracle-marketplace-migrate.js all
```

Forum tables remain in Supabase and are intentionally not included here.

## Blueprint Pricing

Seller listings are priced by collectible dimensions, not by a single card-wide
price. Listing writes in `/api/marketplace-listings` refresh
`public.marketplace_blueprint_price_summary` for only the affected blueprint.
`GET /api/marketplace-cards` and `get_marketplace_home_snapshot(...)` read that
summary for fast native-listing `price` and `stock` values. External marketplace
tile pricing is represented in design language as
`cheapest_homepage_cache_blueprint`: one row per blueprint derived from the daily
backend listings cache/import with eligible Zero + 1-Day Ready count/quantity and
the cheapest effective PKN price when safe. Marketplace/homepage/catalog tile
payloads join this canonical price projection instead of calling CardTrader live
or scanning every snapshot row at render time. If production still exposes
`public.cardtrader_blueprint_listing_cache`, that is the legacy/compatibility
physical table name until a migration renames it. It is not a fallback behind old
stock logic. Card detail seller rows keep using the live parser.

Useful diagnostics:

```bash
node scripts/debug-marketplace-prices.js 316600
```

The full operating runbook is in
`../workflows/oracle-marketplace-postgres-workflow.md`.

## Runtime Tables

- `public.cardtrader_pokemon_blueprints`: imported CardTrader blueprint source rows.
- `public.cardtrader_pokemon_expansions`: expansion metadata, aliases, and symbols.
- `public.marketplace_cardtrader_import_jobs`: Oracle VM CardTrader import job queue/status rows.
- `public.cardtrader_market_listing_snapshots`: current global CardTrader marketplace product rows from `GET /marketplace/products`.
- `cheapest_homepage_cache_blueprint`: canonical design concept for the analytics/Postgres cheapest eligible Zero + 1-Day Ready price projection by blueprint, with EUR/PKN price; currently may be backed by legacy physical table `public.cardtrader_blueprint_listing_cache` until a migration renames it.
- `public.cardtrader_market_listing_removed_history`: previous-day sold/removed global CardTrader listing metadata archived before snapshot deletion.
- `public.cardtrader_user_listing_snapshots`: current per-connected-seller CardTrader product export rows for the seller integration workflow only.
- `public.cardtrader_user_listing_removed_history`: previous-day seller-export removal metadata for connected-seller sync only.
- `public.cardtrader_blueprint_daily_analytics`: per-blueprint CardTrader listing volume, sold count, price movement, and sell-through signals by day.
- `public.marketplace_cards`: lightweight home/catalog card rows.
- `public.marketplace_card_versions`: expansion-scoped version/navigation rows.
- `public.marketplace_search_candidates`: tokenized search/autocomplete projection.
- `public.marketplace_card_events`: raw marketplace interaction events.
- `public.marketplace_card_watchlist_analytics`: lightweight one-row-per-blueprint watchlist counters for marketplace card tile star metrics.
- `public.marketplace_card_watchlist_users`: optional per-user membership keys used to make signed-in watchlist counter updates idempotent.
- `public.marketplace_user_listings`: seller listing source of truth.
- `public.marketplace_price_observations`: append-only raw price facts for seller/external source observations.
- `public.marketplace_blueprint_price_table`: dimensional current prices by blueprint, condition, language, foil/reverse, edition, sealed/signed, graded state, source, and grade.
- `public.marketplace_blueprint_price_summary`: one-row-per-blueprint fast price/stock summary used by home/catalog/search APIs.
- `public.marketplace_hot_blueprints`: 1h/24h/7d hot blueprint rollups used by homepage Best sellers and Featured sections.
- `public.marketplace_firebase_users`: minimal Firebase Auth user dimension for analytics/personalization joins keyed by verified `user_uid`.
- `public.marketplace_variations` and `public.marketplace_card_variations`: structured variation dimensions such as `v`, `ex`, `gx`, `vmax`, `vstar`, `mega`, `lvx`, and tag team.
- `public.marketplace_trainers`: structured trainer/owner aliases.
- `public.cards_type` and `public.cards_name_type`: card type palette classification.

## Public API Consumers

Vercel API functions read Oracle through `MARKETPLACE_DATABASE_URL`:

- `GET /api/marketplace-home`
- `GET /api/marketplace-cards`
- `GET /api/marketplace-card-versions`
- `POST /api/marketplace-search-candidates`
- `POST /api/marketplace-autocomplete`
- `POST /api/marketplace-event`
- `POST /api/marketplace-watchlist`
- `GET|POST|PATCH /api/marketplace-listings`
- `GET|POST /api/cardtrader-daily-listings-refresh` for manual diagnostics only
- `GET /api/marketplace-hot-blueprints?window=1h|24h|7d&limit=50`
- `GET|POST /api/marketplace-debug-cardtrader-blueprints` only queues/reads Oracle import jobs.

## CardTrader Import Jobs

Vercel only queues and reads `public.marketplace_cardtrader_import_jobs`; the
Oracle Cloud VM worker runs the import:

```bash
node scripts/cardtrader-oracle-import-worker.js --poll
```

Install the additive schema first with the normal schema command, then use the
debug panel or the worker `--enqueue` command to create dry-run/apply jobs. Do not
run CardTrader import/image generation inside Vercel serverless functions.

## Hot Blueprint Analytics

Flutter records bounded, non-PII marketplace event metadata through
`/api/marketplace-event`. Raw events are stored in
`public.marketplace_card_events`; `public.refresh_marketplace_hot_blueprints()`
rolls them into `public.marketplace_hot_blueprints`.

The rollup stores event counts and hot scores across `1h`, `24h`, and `7d`
windows. Global daily CardTrader marketplace refreshes run on the Oracle/peer4
host with `scripts/refresh-cardtrader-market-listings.js`; Vercel Cron is not
required. The peer4 job env must include `CARDTRADER_AUTH_TOKEN` or legacy
fallback `CARDTRADER_API_TOKEN` plus `MARKETPLACE_DATABASE_URL` before enabling the cron.
The refresh updates `public.cardtrader_blueprint_daily_analytics`; the hot
rollup folds those listing/sold/sell-through signals into metadata and score.
`public.get_marketplace_home_snapshot(...)` reads this table to produce Best
seller and Featured section IDs, and reads the
`cheapest_homepage_cache_blueprint` projection for canonical tile pricing. If the
SQL still references `public.cardtrader_blueprint_listing_cache`, that is the
legacy physical name for the same projection until a rename migration exists.
CardTrader removed rows are useful
sale/removal signals, not confirmed settled Pokoin sales.

## Firebase User Sync

Firebase Authentication remains the source of truth for accounts. Oracle stores
a minimal user dimension in `public.marketplace_firebase_users` so analytics and
personalization can join verified `marketplace_card_events.user_uid` values to
current account state without storing tokens or secrets.

Apply the additive table, run a dry run, then apply:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/sync-firebase-users-to-oracle.js --limit=25
node scripts/sync-firebase-users-to-oracle.js --apply --limit=all
```

Verification query:

```sql
select
  count(*)::int as total_users,
  count(*) filter (where disabled)::int as disabled_users,
  count(*) filter (where email_verified)::int as email_verified_users,
  max(synced_at) as last_synced_at
from public.marketplace_firebase_users;
```

Targeted refresh:

```bash
node scripts/oracle-marketplace-migrate.js schema
MARKETPLACE_DATABASE_URL=... node -e "const { Pool } = require('pg'); const p = new Pool({ connectionString: process.env.MARKETPLACE_DATABASE_URL, ssl: { rejectUnauthorized: false }}); p.query('select public.refresh_marketplace_hot_blueprints()').then(r => console.log(r.rows)).finally(() => p.end())"
```
