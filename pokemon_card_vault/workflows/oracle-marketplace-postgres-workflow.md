# Oracle Marketplace Postgres Workflow

Use this workflow when changing marketplace/catalog/search storage, migrating
data from Supabase, deploying Oracle-backed marketplace APIs, or cleaning up old
Supabase marketplace objects.

## Current Architecture

- Oracle Postgres is the source of truth for marketplace/catalog/search data.
- Production writes go to the peer4 marketplace Postgres primary.
- Peer3 is the hot-standby fallback, synchronized from peer4 through PostgreSQL
  physical WAL streaming, and is used for card-name search reads.
- Peer2 and peer1 are planned read-only physical replicas for variation and
  search-dimension fanout. They are never write targets.
- Marketplace writes, including manual debug curation, artist upserts, and
  product classification overrides, go to peer4 while peer4 is primary. Physical
  replicas receive those changes automatically through WAL replay; do not apply
  the same write manually to peer3, peer2, or peer1. If a standby is promoted,
  update `MARKETPLACE_DATABASE_URL` and the primary runbook before making more
  writes.
- On 2026-05-22 peer4 reached sustained 100% CPU and was manually rebooted from
  the Oracle panel. Treat peer4 as a recovering writable primary after any such
  event: avoid broad production probes, avoid short-prefix read fallback to
  primary, and keep autocomplete analytics on replicas or skipped for warmups.
- Supabase is retained for forum tables plus an optional derived
  `marketplace_card_name_tokens` searchbar cache only. It is not a marketplace
  DB replica.
- Vercel API functions connect to Oracle through `MARKETPLACE_DATABASE_URL`.
- Global CardTrader market-data ingestion is scheduled and executed on the
  Oracle/peer4 host. Vercel functions may expose read APIs and manual
  diagnostics, but Vercel Cron must not own the daily listing ingestion cadence.
- Flutter must not call Supabase marketplace tables directly.
- Firebase remains the auth/profile/cart/order store. Seller listings are stored
  in Oracle Postgres and authenticated with Firebase ID tokens at the API
  boundary.

## Oracle Runtime Tables

- `public.cardtrader_pokemon_blueprints`
- `public.cardtrader_pokemon_expansions`
- `public.marketplace_cards`
- `public.marketplace_card_versions`
- `public.marketplace_search_candidates`
- `public.marketplace_card_urls`
- `public.marketplace_card_events`
- `public.marketplace_user_listings`
- Global CardTrader market listing snapshots:
  - `public.cardtrader_market_listing_snapshots`
  - `public.cardtrader_market_listing_removed_history`
  - `public.cardtrader_blueprint_daily_analytics`
- CardTrader connected-seller listing snapshots, used only by seller sync:
  - `public.cardtrader_user_listing_snapshots`
  - `public.cardtrader_user_listing_removed_history`
- Blueprint pricing tables:
  - `public.marketplace_price_observations`
  - `public.marketplace_blueprint_price_table`
  - `public.marketplace_blueprint_price_summary`
- `public.marketplace_hot_blueprints`
- `public.marketplace_blueprint_artists`
- `public.marketplace_artist_profiles`
- `public.marketplace_blueprint_tcg_metadata`
- `public.marketplace_blueprint_classification_overrides`
- `public.marketplace_artist_debug_skips`
- `public.marketplace_trainers`
- `public.marketplace_variations`
- `public.marketplace_card_variations`
- `public.cards_type`
- `public.cards_name_type`
- Tokenized search dimensions:
  - `public.marketplace_card_names`
  - `public.marketplace_rarities`
  - `public.marketplace_expansion_numbers`
- Limitless competitive marketplace tables from
  `oracle-postgres/schema/014_limitless_competitive.sql`:
  - `public.limitless_games`
  - `public.limitless_tournaments`
  - `public.limitless_players`
  - `public.limitless_tournament_standings`
  - `public.limitless_tournament_pairings`
  - `public.limitless_decklists`
  - `public.limitless_deck_cards`
  - `public.limitless_sync_runs`

## Runtime API Surface

- `GET /api/marketplace-home`
- `GET /api/marketplace-cards`
- `GET /api/marketplace-card-versions`
- `GET /api/marketplace-artist-cards`
- `GET|POST /api/marketplace-debug-artists`
- `GET|POST /api/marketplace-debug-cardtrader-blueprints`
- `GET /api/marketplace-card-seo`
- `GET /api/marketplace-blueprint-price`
- `GET /api/cardtrader-blueprint-listings?blueprintId=<id>` Oracle/peer4 read
  path for safe CardTrader snapshot metadata by blueprint/card ID
- `GET|POST|PATCH /api/marketplace-listings`
- `GET|POST /api/cardtrader-daily-listings-refresh` for manual diagnostics only,
  if retained during rollout
- `POST /api/marketplace-orders`
- `POST /api/marketplace-search-candidates`
- `POST /api/marketplace-autocomplete`
- `POST /api/marketplace-event`
- `GET /api/marketplace-hot-blueprints`
- `GET /api/marketplace-competitive` for Limitless-backed competitive
  tournament, standings, and pairing snapshots

Supabase is allowed for these bounded roles:

- `GET /api/forum`
- `POST /api/forum-create-topic`
- `POST /api/forum-create-post`
- `POST /api/forum-upload-media`
- Optional backend-only autocomplete name-index reads from
  `public.marketplace_card_name_tokens` when `SUPABASE_NAME_INDEX_DATABASE_URL`
  is configured.

The Supabase name index stores only derived card-name search data: language,
unique display/canonical/search name, normalized/compact name, name tokens,
card ID arrays, representative labels, row count, and search weight. It must not
store user data, listings, prices, events, full blueprint JSON, or marketplace
write surfaces. Oracle peer4 remains the source of truth; peer3/peer2/peer1
remain the Oracle read/fanout fallback architecture.

## Card Detail URL Contract

Canonical marketplace card URLs are generated in Flutter from the real
CardTrader/Pokoin blueprint id and Oracle-projected card metadata:

```text
/marketplace/{lang}/cards/{blueprintId * 2}/{rarity}-{name}-{number}-{set}
/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions
```

Example: Leafeon blueprint `316600` canonicalizes to
`/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions`.

Rules:

- Share links and newly generated internal links should use the canonical
  public-number marketplace URL.
- Legacy numeric marketplace detail URLs remain compatible. Both
  `/marketplace/en/cards/316600-leafeon-005-131-prismatic-evolutions` and
  `/marketplace/en/cards/316600` should resolve by id and canonicalize to the
  public-number URL after the card payload loads.
- The public number is decoded only in canonical two-segment detail paths such as
  `/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions`.
  Do not treat `/marketplace/en/cards/633200` as blueprint `316600`.
- Server-rendered SEO/share previews must follow the same rule. For example,
  `/marketplace/en/cards/248768/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6`
  must divide public number `248768` by 2 and query blueprint/card id `124384`;
  using `248768` as the raw id will show the wrong card in Open Graph/Twitter previews.
- Root numeric short links are accepted only when the root path is digit-only:
  `/316600` renders `CardDetailScreen(cardId: '316600')` directly, then the
  normal resolver canonicalizes to the public-number marketplace URL. Do not
  redirect through `/marketplace/en/cards/:id`, because failed intermediate
  resolution can bounce to `/`.
- Non-numeric root paths remain normal app routes. Do not intercept `/wallet`,
  `/forum`, `/leafeon`, `/rare-leafeon-005-131-prismatic-evolutions`, or
  `/129834-leafeon` as card short links.
- Oracle projections must keep `rarity`, card name, collector number, and set
  name populated enough for stable canonical slug generation. Do not add the
  blueprint id back into canonical slugs to work around missing metadata; fix the
  projection instead.
- Canonical URL rows are materialized in
  `public.marketplace_card_urls`, keyed by `card_id`/blueprint id. The table
  stores the generated English `canonical_slug`, full public-number
  `canonical_path`, and normalized slug/path variants. Human slug collisions can
  exist; uniqueness is required for canonical URL paths. `is_unique`,
  `duplicate_group_size`, and `duplicate_keys` must report zero duplicate URL
  rows after refresh/verifier.

Verify canonical marketplace card URL coverage after URL/projection changes:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify

node scripts/verify-marketplace-card-urls.js \
  --chunk-size=100 \
  --chunks=all \
  --concurrency=32 \
  --pool-max=16
```

The verifier is read-only. It processes logical 100-card chunks in parallel
through a bounded Postgres pool, mirrors the Flutter public-number path shape
`/marketplace/en/cards/{publicNumber}/{rarity}-{name}-{number}-{set}`, and
reports missing required fields, invalid slugs/paths, duplicate canonical paths,
redirect-compatibility failures, and representative examples. Duplicate URL
count must be zero after the materialized table refresh and after the verifier.
If an operator intentionally wants only the historical 400 chunks, pass
`--chunks=400`; use `--limit=<n>` or `--start=<offset>` for targeted probes.

## CardTrader Oracle Import Worker

CardTrader blueprint discovery, raw-row imports, CDN image generation, projection
refresh, and Supabase name-token sync must run on Oracle Cloud, not inside Vercel
serverless functions.

Architecture:

- Vercel exposes only the admin/debug control surface:
  - `GET /api/marketplace-debug-cardtrader-blueprints?game=pokemon` reads the
    latest Oracle job status.
  - `POST /api/marketplace-debug-cardtrader-blueprints` inserts one queued row in
    `public.marketplace_cardtrader_import_jobs`.
- The Flutter debug panel at `/marketplace/debug` can queue a dry-run check and,
  after review/confirmation, queue an apply job. It does not call CardTrader or
  run image/projection work from Vercel.
- The Oracle VM runs `scripts/cardtrader-oracle-import-worker.js`, which claims
  queued jobs with `for update skip locked`, marks heartbeat/progress in Oracle,
  and delegates actual import work to `scripts/cardtrader-multigame-import.js`.
- The active-job unique index allows only one queued/running job per game.

Apply the additive job table on peer4 only:

```bash
node scripts/oracle-marketplace-migrate.js schema
```

The schema file is:

```text
oracle-postgres/schema/009_cardtrader_import_jobs.sql
```

Required Oracle VM env, stored only on the VM:

```env
MARKETPLACE_DATABASE_URL=postgresql://...peer4.../pokoin_marketplace
MARKETPLACE_DATABASE_SSL_VERIFY=0
CARDTRADER_AUTH_TOKEN=
CLOUDFLARE_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
POKOIN_CARD_IMAGES_BUCKET=cardvault-images
POKOIN_CARD_CDN_BASE_URL=https://cdn.pokoin.com
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_PROJECT_REF=
CARDTRADER_IMPORT_WORKER_ID=peer4-cardtrader-import
CARDTRADER_IMPORT_POLL_INTERVAL_MS=30000
```

Manual dry-run enqueue and one-shot processing on the Oracle VM:

```bash
cd /opt/pokemon_card_vault
node scripts/cardtrader-oracle-import-worker.js \
  --enqueue \
  --dry-run \
  --game=pokemon \
  --stream-all \
  --limit=all

node scripts/cardtrader-oracle-import-worker.js --once
```

Manual apply enqueue, bounded to avoid surprise large runs:

```bash
cd /opt/pokemon_card_vault
node scripts/cardtrader-oracle-import-worker.js \
  --enqueue \
  --apply \
  --game=pokemon \
  --stream-all \
  --limit=5000 \
  --images \
  --refresh \
  --sync-search \
  --batch-size=500 \
  --concurrency=4 \
  --image-concurrency=4

node scripts/cardtrader-oracle-import-worker.js --once
```

Continuous polling worker:

```bash
cd /opt/pokemon_card_vault
node scripts/cardtrader-oracle-import-worker.js --poll
```

Recommended systemd unit on the Oracle VM:

```ini
[Unit]
Description=Pokoin CardTrader Oracle import worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pokoin-import
WorkingDirectory=/opt/pokemon_card_vault
EnvironmentFile=/opt/pokemon_card_vault/.env.oracle-cardtrader-import
ExecStart=/usr/bin/node scripts/cardtrader-oracle-import-worker.js --poll
Restart=always
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Install/update sequence:

```bash
sudo useradd --system --home /opt/pokemon_card_vault --shell /usr/sbin/nologin pokoin-import || true
sudo mkdir -p /opt/pokemon_card_vault
sudo chown -R pokoin-import:pokoin-import /opt/pokemon_card_vault

# Copy or git-pull the repository into /opt/pokemon_card_vault, then:
cd /opt/pokemon_card_vault
npm install --omit=dev
sudo install -m 600 -o root -g root .env.oracle-cardtrader-import /opt/pokemon_card_vault/.env.oracle-cardtrader-import
sudo install -m 644 deploy/systemd/pokoin-cardtrader-import-worker.service /etc/systemd/system/pokoin-cardtrader-import-worker.service
sudo systemctl daemon-reload
sudo systemctl enable --now pokoin-cardtrader-import-worker
```

If you prefer timer-driven execution instead of a daemon, run the same script with
`--once` from a `OnCalendar=*:0/5` systemd timer. The DB lock still prevents two
workers from processing the same game concurrently.

Status and diagnostics:

```sql
select
  job_id,
  game,
  mode,
  status,
  request_payload,
  progress,
  summary,
  error_message,
  requested_at,
  started_at,
  heartbeat_at,
  finished_at
from public.marketplace_cardtrader_import_jobs
order by requested_at desc
limit 20;
```

```bash
journalctl -u pokoin-cardtrader-import-worker -f
```

Retry policy:

- Dry-run jobs are safe to queue any time. They do not mutate blueprints, images,
  projections, or Supabase tokens.
- Apply jobs are idempotent for raw blueprint rows (`on conflict do nothing`) and
  image generation overwrites deterministic R2 object keys.
- If a job fails, inspect `error_message`, fix config/source issues, and enqueue a
  new job. Do not manually flip failed rows back to queued unless you also verify
  no worker process is still running.
- If a job is stuck in `running` with an old `heartbeat_at`, stop the worker,
  verify no import process is active, then mark it failed with a clear
  `error_message` before queuing a new job.

## CardTrader Daily Market-Data Ingestion

CardTrader daily public listing ingestion is an Oracle/peer4 host scheduled
job/script. It is not a Vercel Cron job. Keep the schedule close to the peer4
Postgres primary because the job owns marketplace snapshot writes, removed/sold
history, graph/price observation refreshes, CardTrader daily analytics, and
homepage ranking rollups.

Ownership boundaries:

- The Oracle/peer4 host owns the cron schedule, retry loop, dry-run/apply
  execution, and production ingestion cadence.
- Vercel functions serve read APIs and explicit manual diagnostics only. If
  `GET|POST /api/cardtrader-daily-listings-refresh` remains during rollout,
  treat it as an admin diagnostic endpoint, not the daily scheduler.
- `vercel.json` must not contain a `crons` entry for
  `/api/cardtrader-daily-listings-refresh`.
- Per-seller CardTrader connect/sync uses encrypted seller tokens and
  `GET /products/export`; it is separate from global CardTrader market-data
  ingestion, which uses `GET /marketplace/products` and the global app/API token.

Required Oracle job env:

```env
MARKETPLACE_DATABASE_URL=postgresql://...peer4.../pokoin_marketplace
CARDTRADER_AUTH_TOKEN= # or CARDTRADER_API_TOKEN
PKN_CHECKOUT_USDT_PRICE= # optional, defaults to 0.005 for EUR/USD-to-PKN projection
```

`/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env` is the expected host
env file for the peer4 cron on this machine. Confirm it has
`CARDTRADER_AUTH_TOKEN` or the documented fallback `CARDTRADER_API_TOKEN` before
enabling the timer; do not print the token while checking. This peer4 env is
required for the Oracle daily job even when Vercel production also has a
CardTrader token for compatibility/live routes.

Dry-run and bounded probes should use explicit limits before broad production
runs:

```bash
cd /Users/giuseppe/cardvault/pokemon_card_vault
node scripts/refresh-cardtrader-market-listings.js \
  --env-file=/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env \
  --dry-run \
  --blueprint-id=316600 \
  --max-blueprints=25 \
  --max-products=250
```

Daily production sequencing is:

1. Run the full CardTrader market-data import/snapshot refresh with
   `scripts/refresh-cardtrader-market-listings.js`.
2. Only after that command succeeds, derive the analytics/Postgres cheapest
   homepage/catalog tile-price projection with
   `scripts/refresh-cardtrader-blueprint-listing-cache.js`.

The cache refresh must only write the `cheapest_homepage_cache_blueprint`
projection. It must not persist all CardTrader marketplace listings,
removed-history rows, or daily analytics; those remain owned by the full
market-data import/snapshot job. The conceptual pipeline is daily backend
listings cache/import -> cheapest eligible Zero + 1-Day Ready listing per
blueprint -> `cheapest_homepage_cache_blueprint` ->
marketplace/homepage/catalog tile pricing. If production still writes
`public.cardtrader_blueprint_listing_cache`, that is the legacy/compatibility
physical table name until a migration renames it. Do not make tiles call
CardTrader live, and do not treat this projection as a fallback behind old stock
logic.
Manual local runs of either script are emergency/backfill diagnostics only and
should use explicit `--dry-run`, `--blueprint-id`, `--max-blueprints`, or
`--max-products` limits before any broad apply.

Use the peer-host wrapper for the normal daily run:

```bash
cd /opt/pokemon_card_vault
bash scripts/run-cardtrader-daily-market-refresh.sh
```

Example cron entry for peer4 after a successful dry-run:

```cron
20 3 * * * cd /Users/giuseppe/cardvault/pokemon_card_vault && bash scripts/run-cardtrader-daily-market-refresh.sh >> /var/log/pokoin-cardtrader-market-refresh.log 2>&1
```

Equivalent systemd service/timer files are checked in as
`deploy/systemd/pokoin-cardtrader-daily-market-refresh.service` and
`deploy/systemd/pokoin-cardtrader-daily-market-refresh.timer`. Install/update on
the Oracle peer host with:

```bash
cd /opt/pokemon_card_vault
chmod +x scripts/run-cardtrader-daily-market-refresh.sh
sudo install -m 644 deploy/systemd/pokoin-cardtrader-daily-market-refresh.service /etc/systemd/system/pokoin-cardtrader-daily-market-refresh.service
sudo install -m 644 deploy/systemd/pokoin-cardtrader-daily-market-refresh.timer /etc/systemd/system/pokoin-cardtrader-daily-market-refresh.timer
sudo systemctl daemon-reload
sudo systemctl enable --now pokoin-cardtrader-daily-market-refresh.timer
```

If peer3 or peer4 is acting as the writable Oracle primary, install the timer
there only. Physical standbys receive cache rows through WAL replay; do not run
the same write job independently on read-only replicas.

Equivalent inline systemd service shape:

```ini
[Service]
Type=oneshot
WorkingDirectory=/opt/pokemon_card_vault
ExecStart=/usr/bin/env bash scripts/run-cardtrader-daily-market-refresh.sh
```

The apply path should call
`public.refresh_cardtrader_market_listing_snapshots(...)` on peer4. Expected
semantics:

- current marketplace listings upsert into
  `public.cardtrader_market_listing_snapshots`;
- listings missing from the fresh export are archived in
  `public.cardtrader_market_listing_removed_history`;
- removed/sold history rows default to `current_date - 1`, representing the
  previous day's ingestion window;
- current and removed facts project into
  `public.marketplace_price_observations` as `cardtrader_snapshot` and
  `cardtrader_removed_sale`;
- `cheapest_homepage_cache_blueprint` refreshes for touched blueprints as the
  analytics/Postgres canonical cheapest eligible Zero + 1-Day Ready price
  projection, with listing count/quantity and, when safely available, cheapest
  EUR price converted to PKN plus the 200 PKN reserve markup. If production still
  references `public.cardtrader_blueprint_listing_cache`, that is the legacy
  physical table name for this projection until a rename migration exists;
- graph/price observations, blueprint price summaries, CardTrader daily
  analytics, the CardTrader tile-price table, and homepage ranking rollups
  refresh after snapshot writes.

## CardTrader Live And Snapshot APIs

Expose live CardTrader public listing metadata to card pages through the Pokoin
server API so Flutter never receives CardTrader credentials. The live route is:

```text
GET /api/cardtrader-live-listings?blueprintId=316600
GET /api/cardtrader-live-listings?cardId=248856
```

This route answers which CardTrader listings currently have the card. It calls
CardTrader `GET /api/v2/marketplace/products?blueprint_id=:id` with the trusted
server global token (`CARDTRADER_AUTH_TOKEN` or legacy fallback `CARDTRADER_API_TOKEN`) and does
not write Oracle or any database. `blueprintId` is a direct CardTrader blueprint
ID. `cardId` is a Pokoin card ID; numeric values are resolved through Oracle card
data when available and fall back to the same CardTrader blueprint ID. Keep only
short in-process/HTTP caching for repeated page opens. Without `limit`, return
every row CardTrader returns for the blueprint; explicit limits only cap the
client response. Live rows include inferred
`shippingMode`/`shippingLabel` metadata; CardTrader does not expose a direct
shipping-type field, so the route derives `one_day_ready` only from explicit
`1-Day Ready` or `One Day Ready` seller/listing text, then derives `zero` from
`can_sell_via_hub` or `can_sell_sealed_with_ct_zero` when the listing is not
one-day-ready. All remaining listings are `normal`. `max_sellable_in24h_quantity`
alone is not a one-day-ready signal, and professional seller status alone is not
a Zero signal. Regression examples for blueprint `248856`: EeveeRaff and
Mikebarocco are `one_day_ready`; Lolimpodelnerd, Laconteacag, and Card Universe
are `zero`; Tcg-mapro54_cardsita is `normal`. The inferred metadata is not
persisted.

If this live path is served by a Vercel compatibility function, configure
`CARDTRADER_AUTH_TOKEN` or `CARDTRADER_API_TOKEN` in Vercel production. The peer4
host env only covers Oracle scheduled ingestion and does not satisfy Vercel
runtime calls.

The historical/daily snapshot route is:

```text
GET /api/cardtrader-blueprint-listings?blueprintId=316600
GET /api/cardtrader-blueprint-listings?cardId=274416
```

`blueprintId` matches `blueprint_id` or `cardtrader_blueprint_id`. `cardId`
matches `pokoin_card_id`; if the supplied `cardId` is numeric, the read API also
checks the CardTrader blueprint columns for compatibility with card pages that use
the blueprint as the card identity. Keep this route in the Oracle API manifest,
Vercel rewrites, and web packaging while both peer-hosted and compatibility API
paths are available.

The endpoint reads current rows from
`public.cardtrader_market_listing_snapshots`, with `limit`, `page`, and `cursor`
guardrails for large listing sets. It must not call CardTrader live; the live
route above owns on-demand card-page calls. The daily Oracle ingestion job
described above is the only production path that writes snapshot/removed-history
state from CardTrader marketplace products.

Response payloads should expose only safe marketplace metadata, for example:
listing/product ids, CardTrader blueprint id, mapped Pokoin card id, public seller
identity fields, condition, language, quantity, price/currency, sanitized
properties/raw metadata, first/last seen timestamps, and source import/update
timestamps. Do not return CardTrader tokens, app secrets, webhook shared secrets,
encrypted seller secret envelopes, raw ingestion headers, or sensitive raw
metadata keys.

The relationship between tables is:

- `public.cardtrader_market_listing_snapshots` is the current public listing set
  used by the read API.
- `cheapest_homepage_cache_blueprint` belongs to analytics/Postgres design and is
  the canonical cheapest eligible Zero + 1-Day Ready price projection used by
  marketplace/homepage/catalog tile payloads. It is one row per blueprint derived
  from the daily backend listings cache/import and must be read internally from
  Oracle instead of calling CardTrader live for tiles. If production still exposes
  `public.cardtrader_blueprint_listing_cache`, treat it as a legacy/compatibility
  physical table name until a migration renames it. It is not a fallback behind
  old stock logic. Card detail seller listings must keep using the live parser
  for row-level seller, comment, condition, flag, and price metadata.
- `public.cardtrader_market_listing_removed_history` records listings missing
  from the next daily export and supports sold/removed history and graph facts.
- `public.cardtrader_blueprint_daily_analytics` and
  `public.marketplace_price_observations` are derived rollups for chart,
  analytics, and homepage ranking surfaces.

Vercel's role is a proxy/read path when `/api/*` is routed to the Oracle API
service, or a temporary compatibility read function during rollout. Flutter may
call the Pokoin API from card detail pages to show CardTrader current
listings/metadata, but Flutter must never call CardTrader directly and must never
receive secrets. Keep this read endpoint public or lightly cacheable only while
the payload stays limited to already-public listing metadata.

Verification queries:

```sql
select count(*) as current_snapshots
from public.cardtrader_market_listing_snapshots;

select count(*) as cached_available_blueprints
from public.cardtrader_blueprint_listing_cache
where eligible_listing_count > 0
  and cheapest_price_pkn is not null;

select removed_day, count(*) as removed_count
from public.cardtrader_market_listing_removed_history
where removed_day >= current_date - 7
group by removed_day
order by removed_day desc;

select source, count(*) as observation_count
from public.marketplace_price_observations
where source in ('cardtrader_snapshot', 'cardtrader_removed_sale')
group by source;

select observed_day, count(*) as analytics_rows
from public.cardtrader_blueprint_daily_analytics
where observed_day >= current_date - 7
group by observed_day
order by observed_day desc;

select count(*) as hot_blueprint_rows
from public.marketplace_hot_blueprints;
```

## Supabase Name-Index Architecture

Use Supabase only as a derived/cache tier for broad card-name prefix discovery.
It is not a second marketplace database and must be rebuildable from Oracle at
any time.

Ownership boundaries:

- Oracle stores full card rows, listings, users, prices, marketplace events,
  analytics rollups, image fields, and all write surfaces.
- Supabase stores only lightweight search metadata in
  `public.marketplace_card_name_tokens`: one row per `(language, search_name)`
  with display/canonical/search names, normalized/compact name, name tokens,
  complete `card_ids`, representative labels, row count, and rank/search
  weight. The older `public.marketplace_card_name_index` per-card cache may
  remain as rollback state but is not the active backend target.
- Backend API code may query Supabase first for broad 2+ character single-name
  prefixes to get candidate IDs and labels. It must hydrate visible full rows
  from Oracle and cap `rows` to the 20-row preview limit.
- Flutter receives `rows`, `search_context.card_ids`, and lightweight
  `search_context.candidate_labels`; it must not query Supabase directly or
  treat candidate labels as full card data.
- If Supabase is missing, empty, slow, or unhealthy, `/api/searchbar-cards` and
  `/api/marketplace-autocomplete` fall back to Oracle peer/name replica paths.

Operational gates:

- Do not mutate Supabase until the schema SQL and dry-run counts have been
  reviewed.
- Do not add prices, listings, users, full blueprint JSON, or write endpoints to
  Supabase.
- Keep RLS enabled on the public name-index table. Backend and sync scripts use
  server-side credentials; client code does not read this table.
- Treat Supabase as disposable cache state: if data quality is suspect, rebuild
  from Oracle rather than patching rows manually.

## Required Environment

Read from `.env.local` or Vercel env. Never print secret values.

```bash
MARKETPLACE_DATABASE_URL=
MARKETPLACE_DATABASE_SSL_VERIFY=0
MARKETPLACE_NAME_SEARCH_DATABASE_URL= # optional peer3 name-search replica
MARKETPLACE_PEER4_DATABASE_URL= # optional explicit peer4 primary alias
MARKETPLACE_PEER3_DATABASE_URL= # optional explicit peer3 name/search replica
MARKETPLACE_PEER2_DATABASE_URL= # optional explicit peer2 dimension/read replica
MARKETPLACE_PEER1_DATABASE_URL= # optional explicit peer1 dimension/read replica
MARKETPLACE_NUMBER_SEARCH_DATABASE_URL= # optional collector-number source override
MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL= # optional expansion-name source override
MARKETPLACE_RARITY_SEARCH_DATABASE_URL= # optional rarity source override
MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL= # optional variation/owner source override
MARKETPLACE_DIMENSION_SEARCH_TIMEOUT_MS=1200
MARKETPLACE_DIMENSION_SEARCH_DATABASE_POOL_MAX=2
MARKETPLACE_PREDICTIVE_POOL_ENABLED= # set 1 to enable strict predictive pool path
MARKETPLACE_PREDICTIVE_POOL_STRICT=1
MARKETPLACE_NAME_SEARCH_TIMEOUT_MS=1500
MARKETPLACE_NAME_SEARCH_CIRCUIT_MS=60000
MARKETPLACE_VARIATION_SEARCH_DATABASE_URL= # optional single peer2/peer1 dimension replica
MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS= # optional comma-separated peer2,peer1 URLs
MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS= # optional comma-separated analytics read replicas
MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH=1
MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS=1500
MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS=60000
FIREBASE_PROJECT_ID= # Firebase Admin user sync
FIREBASE_CLIENT_EMAIL= # Firebase Admin user sync
FIREBASE_PRIVATE_KEY= # Firebase Admin user sync
SUPABASE_DB_URL= # migration/copy/cleanup only
SUPABASE_DB_POOLER_URL= # optional Supabase pooler target for operator scripts
SUPABASE_NAME_INDEX_DATABASE_URL= # optional backend-only derived card-name index; falls back to SUPABASE_DB_URL when unset
SUPABASE_NAME_INDEX_DATABASE_POOL_MAX=2
SUPABASE_NAME_INDEX_DATABASE_SSL_VERIFY=0
SUPABASE_URL= # forum only
SUPABASE_ANON_KEY= # forum only
SUPABASE_SERVICE_ROLE_KEY= # forum writes only
```

Local Firebase CLI is already authenticated in this operator environment. If a
marketplace workflow needs Firebase user/profile diagnostics, run read-only
Firebase CLI checks directly instead of blocking on login. Deployed Vercel APIs
still use Firebase Admin env vars, not local CLI auth.

The Oracle user dimension sync also uses Firebase Admin credentials from
`.env.local` or the process environment. It stores only minimal account metadata
in `public.marketplace_firebase_users`; never store Firebase bearer tokens,
refresh tokens, password hashes, or custom claims in Oracle.

Production deploy requires `MARKETPLACE_DATABASE_URL` in Vercel. The deploy
script intentionally refuses to publish without it. Production search splitting
also requires `MARKETPLACE_NAME_SEARCH_DATABASE_URL` so card-name matching can
run on peer3 while non-name fields stay on peer4. Keep
`MARKETPLACE_NAME_SEARCH_TIMEOUT_MS` and `MARKETPLACE_NAME_SEARCH_CIRCUIT_MS`
in Vercel production as well; they are read by
`/api/marketplace-search-candidates` so a slow or unreachable peer3 replica
degrades quickly to peer4 full search.

CardTrader Vercel compatibility routes that call live CardTrader listings also
require `CARDTRADER_AUTH_TOKEN` or `CARDTRADER_API_TOKEN` in Vercel production.
The Oracle/peer4 daily job separately needs the same token family in the peer4
env file used by its cron or systemd timer.

Request-time APIs must not depend on newly introduced Oracle helper functions
before the schema has been applied in production. If an endpoint needs a simple
normalization such as stripping a leading `#` from collector numbers, keep an
application-code fallback in the endpoint query/mapper. Use schema helpers for
projection refresh and persisted cleanup, but do not let homepage/search APIs
500 solely because deploy order applied code before SQL.

When adding or exposing an Oracle-backed endpoint, update both `vercel.json` and
`deploy-pokoin-web.sh`. The endpoint file must be copied to `build/web/api`,
required helpers must be copied to `build/web/server`, and the deploy script
should assert critical files exist before `vercel deploy`.

Variation/search-dimension fanout can also move off peer4 after peer2 and peer1
are bootstrapped as physical replicas:

- Prefer `MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` with peer2 and peer1 URLs,
  comma-separated, for round-robin read distribution.
- Alternatively set explicit peer aliases:
  `MARKETPLACE_PEER4_DATABASE_URL` for the writable primary,
  `MARKETPLACE_PEER3_DATABASE_URL` for name/predictive reads, and
  `MARKETPLACE_PEER2_DATABASE_URL` plus `MARKETPLACE_PEER1_DATABASE_URL` for
  dimension/analytics read replicas. Existing env names still take precedence.
- Use `MARKETPLACE_VARIATION_SEARCH_DATABASE_URL` only when a single dimension
  replica is available.
- Set `MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS` when analytics should use a
  different replica set. If unset, analytics read routing uses peer2/peer1/peer3
  when configured and only falls back to peer4 when no replicas exist.
- Keep `MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH=1` in production. This
  skips analytics for one-character warmups; temporarily use `2` if peer4 or
  replicas are under pressure and two-character warmups need to be lighter.
- Keep `MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS` and
  `MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS` short. If the configured dimension
  replica path times out or errors, the API opens a temporary circuit and falls
  back to peer4 non-name search.
- Leave these env vars unset until replicas are healthy; unset variables keep
  all non-name reads on `MARKETPLACE_DATABASE_URL`.
- Broad one- and two-character autocomplete fallback must not hammer peer4. If
  name/replica reads are unavailable for short prefixes, return an empty or
  lightweight typed response and let the next keystroke retry replicas.
- The new predictive 5000 pool path is opt-in and strict by default. In strict
  mode, missing required dimension routes or source query failures are returned
  as explicit debug/error state (`PREDICTIVE_POOL_SOURCE_FAILED`) rather than
  silently falling back to peer4, hot rows, or a generic ranked pool. Keep it
  enabled only in development/preview until peer1/peer2 and Supabase routes are
  provisioned and verified.
- Dimension routing is by source, not row range: collector numbers prefer peer2
  or `MARKETPLACE_NUMBER_SEARCH_DATABASE_URL`; expansion names prefer peer1 or
  `MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL`; rarity prefers peer3/name-search
  or `MARKETPLACE_RARITY_SEARCH_DATABASE_URL`; variation/owner prefers peer2 or
  `MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL`. If peer1/peer2 are not
  configured, strict predictive pool requests should fail visibly instead of
  broadening to peer4.

Local `.env.local` should include both database URLs:

- `MARKETPLACE_DATABASE_URL` points to peer4, the writable primary.
- `MARKETPLACE_NAME_SEARCH_DATABASE_URL` points to peer3, the read-only
  card-name search replica.
- `MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` points to peer2 and peer1 after
  both are read-only replicas and replication health checks pass.

Do not add `sslmode=require` to the local peer4 URL unless the local Node
runtime trusts the peer4 certificate. The project runtime uses
`ssl: { rejectUnauthorized: false }`, so the reachable local setup is the plain
Postgres URL plus `MARKETPLACE_DATABASE_SSL_VERIFY=0`.

## Peer4 Primary / Peer3 Fallback

The peer3 fallback workflow lives in the `pokoinpos` repo:

```bash
open /Users/giuseppe/pokoinpos/docs/operations/postgres-peer3-fallback.md
```

Rules:

- Apply marketplace schema/data changes to peer4 only while peer4 is primary.
- Do not write to peer3 while it is a standby.
- Only card-name search reads may use peer3 through
  `MARKETPLACE_NAME_SEARCH_DATABASE_URL`.
- After every schema/import/projection refresh, verify peer3 replication health.
- If peer3 is lagging or unavailable, search code must fall back to peer4 full
  search instead of failing autocomplete.
- Streaming replication does not replace encrypted backups.
- If peer3 is promoted, update Vercel `MARKETPLACE_DATABASE_URL` to peer3 before
  redeploying the web/API project, and re-seed old peer4 before returning it to
  service.

## Peer2 / Peer1 Variation Replicas

Peer2 and peer1 should use the same physical streaming replica scripts as
peer3, but with unique env files, data directories, container names, public
hosts, and replication slot names. Do not reuse peer3's slot or data directory.

Create env files in `pokoinpos` by copying the peer3 example:

```bash
cd /Users/giuseppe/pokoinpos
cp deploy/env/peer3-postgres-replica.env.example deploy/env/peer2-postgres-replica.env
cp deploy/env/peer3-postgres-replica.env.example deploy/env/peer1-postgres-replica.env
```

For each replica env file, set:

- `MARKETPLACE_DB_CONTAINER_NAME` to a host-unique name such as
  `pokoin-marketplace-postgres-peer2-replica`.
- `MARKETPLACE_DB_PUBLIC_HOST` to that peer's public host/IP.
- `MARKETPLACE_DB_DATA_HOST_PATH` to a peer-specific Postgres data directory.
- `MARKETPLACE_DB_PRIMARY_HOST` to peer4.
- `MARKETPLACE_DB_REPLICATION_SLOT` to a unique slot such as
  `pokoin_peer2_replica` or `pokoin_peer1_replica`.
- `MARKETPLACE_DB_PASSWORD` and `MARKETPLACE_DB_REPLICATION_PASSWORD` to the
  same values used by the peer4 primary.
- `MARKETPLACE_DB_ALLOWED_CIDRS` to trusted API/Vercel/operator CIDRs only.

Update peer4's `MARKETPLACE_DB_REPLICA_CIDRS` to include peer3, peer2, and peer1
CIDRs, then safely apply only the primary-side replication role/HBA update:

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-primary-replication-setup.sh deploy/env/peer4-postgres.env
sudo deploy/scripts/postgres-firewall.sh deploy/env/peer4-postgres.env
```

Bootstrap each replica only on its own peer host. This command wipes the
configured `MARKETPLACE_DB_DATA_HOST_PATH`; confirm the env file and directory
before running:

```bash
sudo deploy/scripts/postgres-init-tls.sh
deploy/scripts/postgres-replica-bootstrap.sh deploy/env/peer2-postgres-replica.env --confirm-wipe-replica-data
./deploy/scripts/docker-postgres-up.sh deploy/env/peer2-postgres-replica.env
sudo deploy/scripts/postgres-firewall.sh deploy/env/peer2-postgres-replica.env
```

Repeat with `peer1-postgres-replica.env` on peer1. After both replicas are up,
verify each one:

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer2-postgres-replica.env
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer1-postgres-replica.env
```

Only after `pg_is_in_recovery()` is true and replay delay is acceptable should
Vercel/local API env be updated:

```bash
MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS=postgresql://...peer2.../pokoin_marketplace?sslmode=require,postgresql://...peer1.../pokoin_marketplace?sslmode=require
MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS=postgresql://...peer2.../pokoin_marketplace?sslmode=require,postgresql://...peer1.../pokoin_marketplace?sslmode=require,postgresql://...peer3.../pokoin_marketplace?sslmode=require
MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS=1500
MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS=60000
MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH=1
```

Do not run migrations, refreshes, listing writes, events, or failover promotion
against peer1 or peer2 while they are read replicas.

## Search Autocomplete Debug Workflow

Use the top-bar search debugger as `vitologiuseppe17` and export the trace after
typing a few realistic searches character by character. The trace should be read
from frontend to backend in this order:

- `flutter.input.changed` proves the exact text Flutter saw.
- `provider.preview.input`, `provider.preview.debounce_fire`, and
  `provider.preview.load_start` show debounce timing, request ids, language, and
  whether autocomplete is visible yet.
- `provider.preview.local_disabled` confirms Flutter is not locally ranking or
  merging cached suggestions for preview autocomplete.
- `service.autocomplete.request`, `service.autocomplete.response`,
  `service.autocomplete.error`, and `service.autocomplete.debug` show Vercel/API
  latency, retries, DB path, candidate rows, ranking score, and matched terms.
- `provider.preview.remote_response`, `provider.preview.remote_drop_stale`, and
  `provider.preview.render` show whether the response was accepted, dropped as
  stale, or rendered.

Historical trace `search-1779282913705-3dbb1` showed the important failure modes:

- Flutter once launched remote autocomplete for hidden 2-character warmups such
  as `fl`, `fo`, `la`, `az`, and `n b`. Current behavior intentionally starts
  remote autocomplete at one meaningful character, so one-character queries must
  stay bounded to hot/ranked data and never become unbounded full-catalog scans.
- Timed-out autocomplete calls were retried automatically, so one fast typing
  burst could double the number of in-flight API calls. This created repeated
  `TimeoutException after 0:00:06` entries and late responses.
- Same-pool stale responses were allowed to render. For example, the `fol`/`folt`
  pool was later rendered for the active `folteon prism` text, which produced
  confusing results even though the latest typed query was more specific.
- Peer3 name search can time out after `MARKETPLACE_NAME_SEARCH_TIMEOUT_MS`.
  When it does, the API opens the name-search circuit and falls back to peer4
  `primary_full_circuit_open`. That prevents a hard failure, but it can still be
  3-6 seconds if the requested pool is too large.
- Ranking quality is strongest when the query includes stable intent tokens:
  `lapras v`, `lapras gx`, and `azelf lvx` ranked correctly. Typo cases such as
  `folteon prism` and `n blakc with` now depend on API ranking only; do not
  reintroduce local preview pools to paper over weak backend results.

Current guardrails:

- Autocomplete remote warmup and visible overlay start at one meaningful
  character. Empty focus uses the server-cached top 1000 analytics-hot
  marketplace cards/products, prepends up to the two most recent viewed
  blueprints on the client, and renders only the first 20 rows while the user is
  about to type.
- The first typed character is remote-authoritative and replaces that hot pool
  with a bounded 1000-row Pokemon/card name-prefix pool. Analytics/hot data can
  rank rows inside the prefix pool, but generic hot rows that do not start with
  the typed character must not render.
- `marketplace_card_events` stores site events for anonymous users and can store
  `user_uid` from a verified Firebase bearer token. APIs must never store raw
  bearer tokens. User boosts are read only for the already matched candidate ids,
  so personalization cannot inject unrelated hot cards into typed autocomplete.
- The Flutter provider drops every stale remote response by request id, even if
  it shares a candidate pool key with the current query.
- Autocomplete uses one API attempt per keystroke. Full search can still use its
  own retry/fallback behavior, but preview typing should not create retry storms.
- Flutter requests the visible preview limit (`result_limit=20`) plus a
  background pool limit (`pool_limit=1000`) for typed autocomplete. The API ranks
  the 1000-candidate preview pool remotely and returns only the visible rows plus
  compact pool/search context.
- The empty-focus cache comes from either an empty
  `POST /api/marketplace-autocomplete` or
  `GET /api/marketplace-hot-blueprints?includeCards=1&limit=1000`. The endpoint
  caps `limit` at 1000, returns compact card rows only when `includeCards` is
  requested, and caches the server-side hot pool for roughly 60 seconds with
  stale revalidation.
- Fixed or hardcoded local preview pools should not be reintroduced. Cached
  preview rows may come from the dynamic hot-card cache only, and typed queries
  must still let remote autocomplete provide the authoritative ranking.
- The API records `candidateDurationMs`, `rankDurationMs`, `searchPath`,
  `poolSource`, `poolSize`, `replicaPath`, `replicaFallback`,
  `nameSearchDisabledUntil`, `fallback.reason`, `debugAuthError`, `tokenPlan`,
  and ranked `matchedTerms` when debug is enabled.

Current two-DB search behavior:

- Peer3 and peer4 are split by search dimension, not by token intersection.
  Peer3 handles name candidates through
  `search_marketplace_blueprint_name_candidates`; peer2/peer1 handle non-name
  dimension fanout when `MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` is set.
  Peer4 handles non-name dimensions when replica env is unset, when the
  dimension replica circuit is open, or as the full fallback path.
- The opt-in predictive pool path (`MARKETPLACE_PREDICTIVE_POOL_ENABLED=1`) is a
  stricter development path layered beside the existing autocomplete behavior.
  Supabase first returns the top provisional predicted card-name tokens for the
  current typed name fragment. Oracle/Postgres then validates the remaining
  typed tokens against dimension routes: collector number on peer2 or
  `MARKETPLACE_NUMBER_SEARCH_DATABASE_URL`, expansion/set on peer1 or
  `MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL`, rarity on peer3 or
  `MARKETPLACE_RARITY_SEARCH_DATABASE_URL`, and variation/owner on peer2/peer1
  or `MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL`.
- The predictive path merges by `card_id`, records predicted tokens,
  confidence, source flags, source route status, and score components, and
  returns up to 5000 lightweight IDs/labels while full `rows` stay capped to 20.
  Unlike legacy paths, it does not use broad primary/peer4 fallback for missing
  required Supabase or dimension sources while `MARKETPLACE_PREDICTIVE_POOL_STRICT`
  is on. If no token for a dimension was typed, that dimension route is not
  required.
- Typed autocomplete uses a predictive ngram index for the whole input, not only
  first-character alphabet ranges. `marketplace_name_ngrams` stores 2- and
  3-character consecutive compact chunks for canonical, display, and localized
  card names, linked back to `marketplace_search_candidates.card_id`.
  `marketplace_query_chunk_events` stores aggregate observed query chunks and
  chunk transitions from search events without keeping a raw query history.
- `/api/marketplace-autocomplete` extracts chunks from the current typed input,
  queries the ngram index for a bounded candidate id pool, filters by structured
  number/variation/set tokens when present, then ranks by chunk/text match
  quality, typo/fuzzy distance and coverage, structured token matches, site hot
  analytics, and optional user personalization inside that candidate pool.
- Peer3/peer2/peer1 remain execution infrastructure for legacy paths. In the
  strict predictive pool path, missing peer1/peer2/peer3 or specialized
  dimension envs are visible source failures for dimensions that were actually
  typed; peer4 is protected from broad predictive fallback. Do not provision
  peer1/peer2 from this app repo.
- Debug for `typed_predictive_ngrams` must expose chunks used, candidate counts,
  fallback/schema status, duration, matched chunks, fuzzy/relevance scores, and
  analytics boosts. The merge dedupes by blueprint/card id and ranking stays
  inside matching candidates only.
- Autocomplete now prefers a candidate fanout path for multi-token queries:
  canonical/name-table matches seed a small candidate set, then Node applies
  targeted checks for number, variation, expansion/set, trainer, rarity, and
  product variant fields before ranking. For example, `flareon ex` starts from
  `flareon` candidates, then validates `variation:ex`.
- Variation-prefix refinements such as `mimikyu g` and `mimikyu e` are variation
  intent before expansion intent: they must validate stored variation identity
  (`GX`/`EX` in `product_variant` or `marketplace_card_variations`) before set
  names like `GX Battle Boost` can compete.
- Plain name prefixes without a variation token, such as `pikac`, should prefer
  base display-name prefix rows (`Pikachu`) over suffix variants (`Pikachu GX`,
  `Pikachu ex`). Popularity and depth boosts may order rows inside the same
  tier, but should not lift suffix variants above the base display-name tier
  until the user types a variation token.
- Non-intersection queries still use the split ranked pool: peer3 name rows and
  peer4 non-name rows are unioned/deduped, then SQL and Node ranking reward rows
  that match multiple tokens.
- Incremental refinement is part of the preview pool contract. When the user
  extends a query, for example `mew` -> `mew 2` -> `mew 232`, the API may accept
  a compact previous `search_context` with up to 1000 `card_id` values and query
  only those ids before falling back to normal fanout.
- Prefix refinement follows the same contract for `p` -> `pi` -> `pik` ->
  `pika`: each response must be a matching backend candidate pool ranked within
  that pool. For two or more compact characters, the predictive ngram index is
  preferred; one-character prefix sharding is only a compatibility fallback.
  Generic hot fallback rows are allowed only for empty focus, not after typing
  starts, and Flutter may only dedupe exact ids while preserving backend order
  for typed preview and full-search results.
- Rarity phrase queries such as `mew special illustration rare` intentionally
  stay on the ranked-pool path for now because the rarity intent can span several
  words and should not be split into independent required tokens yet.
- Flutter autocomplete previews are remote-authoritative for typed queries. The
  dynamic hot-card cache may provide instant interim rows and empty-focus rows,
  but remote responses replace typed preview rows when the latest request still
  matches the current query.
- Flutter full-search state is also remote-authoritative for typed queries:
  backend-ranked blueprint/card rows may be deduped by exact ID, but active
  `filteredCards` must preserve backend order. Do not merge typed results into a
  local/hot cache and then filter or alphabetically sort that cache for display.

Target token-intersection behavior:

- For structured multi-token queries, classify each token before querying:
  name text (`flareon`), variation (`ex`, `v`, `gx`, `vmax`), number, rarity,
  expansion alias, product term, or language/condition dimension.
- Fetch name/text candidates from peer3/name search, but do not depend only on
  that RPC for exact names. If a valid exact name token returns zero rows (for
  example `manaphy`), fall back to `marketplace_search_candidates` with compact
  exact/prefix matching before applying structured filters.
- Root-cause check for zero name rows: inspect expansion-alias collisions before
  assuming missing card-name data. CardTrader expansion codes can be real Pokemon
  names (`manaphy`, `mew`, `latias`, `gyarados`, `lucario`, etc.). The name RPC
  must not drop a token merely because it also exists in
  `marketplace_expansion_aliases`; card-name matches take precedence in the
  name-search path.
- Multilingual name matching uses fixture-backed per-language tables:
  `marketplace_card_names_en`, `marketplace_card_names_it`,
  `marketplace_card_names_fr`, `marketplace_card_names_de`,
  `marketplace_card_names_es`, `marketplace_card_names_pt`,
  `marketplace_card_names_ja`, `marketplace_card_names_zh_cn`, and
  `marketplace_card_names_zh_tw`. Rebuild them with
  `node scripts/import-fixture-card-name-languages.js` after applying schema or
  updating `test/fixtures/pokemon_card_names_by_generation.txt`.
- The search RPC selects names through
  `marketplace_card_names_for_language(search_language)`. Unsupported UI
  languages such as `nl`, `pl`, `ru`, `ko`, `id`, and `th` currently fall back to
  English until fixture rows exist for them.
- Canonical card identity is projected separately from CardTrader display text:
  `source_name` and `display_name` preserve the original name, `canonical_name`
  stores the searchable identity, `product_variant` stores suffix/prefix variants
  such as `Surfing`, `GX`, `EX`, `VMAX`, and `Mega EX`, and `trainer_name` stores
  owner prefixes such as `Lt. Surge` or `Ash`.
- The canonical parser uses `marketplace_pokemon_name_roots`, imported by
  `node scripts/import-fixture-card-name-languages.js`. The root table is built
  from the fixture Pokémon sections only; the `## Trainers` section is excluded
  so trainer/supporter/item names such as `Cynthia` and `Rare Candy` remain full
  canonical names.
- Trainer-owned Pokémon are Pokémon cards with trainer metadata:
  `Lt. Surge's Pikachu` projects to `canonical_name = Pikachu` and
  `trainer_name = Lt. Surge`. Actual Trainer/Supporter/Item/Stadium cards keep
  the full name as `canonical_name`.
- Name matching in the RPC joins through `canonical_name`; variant matching uses
  `product_variant`/`marketplace_card_variations`, and trainer matching uses
  `trainer_name`. This prevents expansion typo tokens such as `surgin` from
  competing with `Surfing Pikachu` as if `Surfing` were the Pokémon name.
- Apply structured dimensions against stored tables for the current name working
  set. Variation tokens must be validated with `marketplace_card_variations`;
  collector numbers with compact `card_number`; expansion aliases with compact
  `set_name`/alias targets. Do not require the card to appear in a capped generic
  peer4 result set for `ex`, `v`, `vmax`, etc.
- Structured intersections should use the full backend token range, not the
  visible preview pool size. For queries like `mew 232`, the exact matching row
  can sit beyond the first 100 name candidates and must still survive until the
  collector-number filter is applied.
- Collector number filters must match numeric tokens anywhere in normalized
  `card_number`, not only at the compact prefix. Values like
  `Special Illustration Rare | 232/091` must match `232`.
- Intersect required tokens before ranking. For `flareon ex` or `manaphy ex`,
  the working set should become `name-token candidates filtered by stored
  variation:ex`, so the API ranks the real matching candidate set instead of
  sorting hundreds of unrelated `ex` rows.
- Use union only for synonyms and aliases inside the same token family, such as
  `ex` aliases or localized name matches. Use intersection across different
  user-intent tokens.
- For typed query extensions, prefer stateless ID-bounded refinement before a
  fresh fanout: if the request includes a valid previous context with the same
  language and a prefix query, filter
  `marketplace_search_candidates.card_id = any(previous_ids)` and then apply the
  same stored field checks. Reject stale, shortened, cross-language, or oversized
  contexts and fall back to normal fanout.
- Debug traces for this path include `candidateDebug.tokenPlan`, per-token
  `rawRowCount`, `fallbackRowCount`, `rowCount`, `storedDimensionFilter`,
  `nameIntersectedRowCount`, `intersectedRowCount`, optional `fallbackReason`,
  and final ranked rows.
- Future work: make rarity phrases, product facets, language, condition, reverse,
  first edition, and graded dimensions part of the same token-planning model once
  those dimensions are explicitly represented as searchable facet sets.

When debugging a new trace, treat any of these as regressions:

- A stale request renders after a newer `previewRequestId` exists.
- A one-character query uses anything other than the bounded
  `hot_one_character`/hot-ranked path.
- Empty focus shows a spinner instead of cached hot cards after the hot cache has
  been populated.
- A fixed, hardcoded, or curated local preview pool appears in Flutter instead of
  the dynamic hot-card cache.
- One keystroke generates attempt 2 unless the code path is a deliberate full
  search, not preview autocomplete.
- Flutter records `provider.preview.local_rank`, calls
  `CardService.searchCardPreviews(...)`, or merges fallback/local cards before
  assigning `state.searchPreviews`.
- `service.autocomplete.response.elapsedMs` repeatedly exceeds 3000 ms for
  normal names like `lapras`, `azelf`, or `flareon`.
- Ranked rows have empty `matchedTerms` for a clearly name-driven query.
- A structured query like `flareon ex`, `charizard 199`, or `umbreon vmax` ranks
  broad single-token rows above rows matching the full token intersection.
- A structured query like `mew 232`, `mew ex 232`, or typo `mee 232` returns no
  rows even though `search_marketplace_blueprint_non_name_candidates('232', ...)`
  finds the target row. Check for a capped name working set and for
  collector-number filtering that only uses `startsWith`.
- A non-English query like `florizarre ex` with `search_language = 'fr'` returns
  base `Venusaur` rows for `florizarre` but no structured `Venusaur ex` rows.
  Check that per-language tables are imported and that Node does not re-filter
  localized SQL hits against English `row.name`.
- A Pokemon suffix token such as `ex`, `gx`, `v`, `vmax`, `vstar`, `mega`, or
  `lv x` is classified as rarity/text instead of `variation`. Queries like
  `manaphy ex` or typo variants such as `mapahy ex` must plan
  `name-token ∩ variation-token`; if `debug.tokenPlan` is `ranked_pool` or
  missing, the backend can fall back to broad `ex` rows such as unrelated
  `Absol ex`.
- A structured query reports `empty_intersection` after fetching a generic
  top-N `ex`/`v`/`vmax` pool. That pool can be biased toward high-rank names like
  `Absol ex` and omit lower-ranked but valid rows such as `Manaphy ex`. The
  correct path is `name_first_stored_dimension_intersection`.
- A query like `pikachu surgin` ranks `Surfing Pikachu` above Surging Sparks
  cards/products. Check that `marketplace_search_candidates.canonical_name` is
  populated, `refresh_marketplace_token_search_index()` has rebuilt
  `marketplace_card_names` from canonical names, and the search RPC is joining
  name hits on `coalesce(nullif(canonical_name, ''), name)`.
- A plain trainer card query like `cynthia` ranks `Cynthia's Ambition` above
  exact `Cynthia`. Check the exact canonical-name boost in the RPC and confirm
  actual trainer cards were not parsed as Pokémon owner prefixes.
- `search_marketplace_blueprint_name_candidates('manaphy', ...)` returning zero
  while `marketplace_search_candidates` contains compact exact/prefix matches.
  Treat this as a name-RPC diagnostic, not as proof the card does not exist. Run
  an alias-collision query against `marketplace_expansion_aliases` and
  `marketplace_card_names`. If the token exists in both tables, patch/apply
  `003_marketplace_search_rpc.sql`; autocomplete's exact-name fallback is only a
  safety net.

## Apply Or Refresh Oracle

Run from `pokemon_card_vault`:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

The migration script auto-loads `.env.local`, so these commands should work
without manually exporting `MARKETPLACE_DATABASE_URL`. If Vercel production env
is updated, mirror the peer4 primary URL into `.env.local` before local schema
or refresh commands.

If a full refresh times out while rebuilding projections, do not assume schema
failed. Check the targeted readiness probes:

```bash
node - <<'NODE'
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.MARKETPLACE_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  max: 1,
});
(async () => {
  const table = await pool.query(
    "select to_regclass('public.marketplace_user_listings') as table_name",
  );
  const home = await pool.query(
    "select jsonb_array_length(public.get_marketplace_home_snapshot(1)->'cards') as cards",
  );
  console.log('listing_table=' + (table.rows[0].table_name ? 'ok' : 'missing'));
  console.log('home_snapshot_cards=' + home.rows[0].cards);
})().finally(() => pool.end());
NODE
```

Canonical marketplace URLs are refreshed by
`public.refresh_marketplace_oracle_projections()` after
`marketplace_search_candidates` is rebuilt. Targeted URL-only refresh and
verification:

```sql
select public.refresh_marketplace_card_urls();

select
  count(*)::int as url_rows,
  count(*) filter (where is_unique)::int as unique_rows,
  count(*) filter (where not is_unique)::int as duplicate_rows,
  count(distinct card_id)::int as distinct_cards,
  count(distinct canonical_path)::int as distinct_paths,
  count(distinct canonical_path_normalized)::int as distinct_normalized_paths,
  max(duplicate_group_size)::int as max_duplicate_group_size,
  max(updated_at) as last_updated_at
from public.marketplace_card_urls;

select *
from public.marketplace_card_url_duplicate_report()
limit 50;

select card_id, canonical_path, duplicate_group_size, duplicate_keys
from public.marketplace_card_urls
where not is_unique
order by duplicate_group_size desc, canonical_path, card_id
limit 50;
```

`node scripts/oracle-marketplace-migrate.js verify` runs the duplicate report and
prints counts plus sample collision groups. A fully unique URL scheme should have
`duplicate_rows = 0` and an empty `marketplace_card_url_duplicate_report()`.
After the 2026-05-22 public-number URL refresh, production Oracle had `70,021`
rows in `public.marketplace_card_urls` and `0` duplicate canonical paths. The
targeted URL-table refresh was used because the full projection refresh timed
out; keep that path available for future URL-only fixes.

Run the full URL verifier after the table refresh:

```bash
node scripts/verify-marketplace-card-urls.js --chunk-size=100 --chunks=all --concurrency=32 --pool-max=16
```

The verifier must report zero duplicates. It should include representative
canonical examples such as Leafeon `316600` ->
`/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions` and Fan
Rotom `316698` ->
`/marketplace/en/cards/633396/common-fan-rotom-085-131-prismatic-evolutions`.

Then verify the peer3 fallback from the `pokoinpos` repo:

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer3-postgres-replica.env
```

If peer2/peer1 variation replicas are configured, verify them as well:

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer2-postgres-replica.env
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer1-postgres-replica.env
```

For initial migration from Supabase:

```bash
node scripts/oracle-marketplace-migrate.js all
```

The `all` command applies schema, copies non-forum marketplace tables from
Supabase, refreshes Oracle projections, and verifies key search queries.
Run the replication status check after `all` as well.

Search/variation changes must live in `oracle-postgres/schema/*.sql`. After
changing variation logic, run both schema and refresh so
`marketplace_card_variations` is rebuilt. Variation tagging should come from
card identity fields (`name`, `card_number`, `rarity`, `card_type`,
`product_variant`) and not from expansion/search text, otherwise sets such as
`Shiny Star V` can incorrectly tag every card in the set as `V`.

### Limitless Competitive Marketplace Import

Use the dedicated Limitless workflow when deploying or refreshing the competitive
marketplace:

```bash
open workflows/limitless-competitive-workflow.md
```

Before expecting `/marketplace/competitive` or
`/api/marketplace-competitive` to return real data, apply the non-destructive
Oracle/Postgres schema on the writable marketplace primary:

```text
oracle-postgres/schema/014_limitless_competitive.sql
```

Then run the sync script. Start with a dry-run and a small apply before the full
or otherwise sensible public import:

```bash
node scripts/sync-limitless-competitive.js --dry-run --game=PTCG --max-tournaments=10
node scripts/sync-limitless-competitive.js --apply --game=PTCG --max-tournaments=10
node scripts/sync-limitless-competitive.js --apply --game=PTCG --max-tournaments=100
```

Public Limitless data may include games, tournaments, standings, and pairings
where the API allows. Restricted decklist endpoints may require Limitless
approval and `LIMITLESS_API_KEY`; treat that as a rollout blocker for full
decklist support, not as data that should be silently assumed.

Do not deploy a frontend-only competitive page unless the empty-state is
intentionally acceptable. The API and UI are data-dependent on the schema and
sync.

### CardTrader Delta Catalog Import

Use the delta importer when CardTrader has released new Pokemon blueprints and a
full catalog copy would be too broad. The script compares CardTrader blueprint
IDs against Oracle `public.cardtrader_pokemon_blueprints`, inserts only missing
raw blueprint rows, and can then call the existing image/projection/Supabase
refresh steps. It is dry-run by default.

Dry-run a focused import from a downloaded CardTrader JSONL file:

```bash
node scripts/cardtrader-delta-import.js \
  --input=data/cardtrader/pokemon-blueprints.jsonl \
  --expansion-ids=4611,4639 \
  --limit=all
```

Or fetch a bounded delta directly from CardTrader by expansion:

```bash
node scripts/cardtrader-delta-import.js \
  --expansion-ids=4611,4639 \
  --limit=all \
  --sleep-ms=100
```

For a full remote delta without writing a local JSONL snapshot, stream CardTrader
expansions page-by-page from the API:

```bash
node scripts/cardtrader-delta-import.js \
  --stream-all \
  --limit=all \
  --sleep-ms=100
```

CardTrader's available catalog endpoint for this workflow is
`/api/v2/blueprints/export?expansion_id=<id>`. It returns full blueprint rows for
one expansion, not an IDs-only feed. Streaming mode therefore avoids a local full
snapshot and compares IDs expansion-by-expansion against Oracle, but it still
reads the remote Pokemon catalog expansion-by-expansion.

Useful focus targets for the current Mega Darkrai check:

- `4611` / `Abyss Eye`
- `4639` / `Pitch Black`
- `--expansion-names="Abyss Eye,Pitch Black"` may be used instead of IDs after
  reviewing the resolved names in the dry-run output.

Review the dry-run output before mutating:

- `counts.fetched`: rows returned from the bounded source.
- `counts.existingRaw`: CardTrader IDs already present in Oracle raw rows.
- `counts.missingRaw`: raw blueprint rows that would be inserted.
- `missingSamples`: representative IDs/names/images to confirm the source is
  the expected expansion and not sealed products.
- `existingRawMissingSearchCandidate`: rows already in raw storage but missing
  derived search candidates, which usually means projections need refresh.

Apply only after the dry-run looks correct:

```bash
node scripts/cardtrader-delta-import.js \
  --apply \
  --input=data/cardtrader/pokemon-blueprints.jsonl \
  --expansion-ids=4611,4639 \
  --limit=all
```

To also generate the three image tiers and refresh search data in the same
bounded or streaming run, include the optional flags:

```bash
node scripts/cardtrader-delta-import.js \
  --apply \
  --input=data/cardtrader/pokemon-blueprints.jsonl \
  --expansion-ids=4611,4639 \
  --limit=all \
  --images \
  --refresh \
  --sync-supabase \
  --languages=en \
  --supabase-transport=rest
```

Streaming apply equivalent:

```bash
node scripts/cardtrader-delta-import.js \
  --apply \
  --stream-all \
  --limit=all \
  --images \
  --refresh \
  --sync-supabase \
  --languages=en \
  --supabase-transport=rest
```

`--images` runs the established image scripts only for newly inserted IDs:

```bash
ORACLE_IMAGE_IDS=<new_ids> node scripts/import-oracle-cardtrader-images.js
node scripts/generate-oracle-homepage-card-images.js --apply --ids=<new_ids> --limit=all
```

The image phase requires the existing R2/CDN environment
`CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`POKOIN_CARD_IMAGES_BUCKET`, and `POKOIN_CARD_CDN_BASE_URL` when configured.
It should not be replaced with ad hoc object writes. If those credentials are
missing, run the dry-run/import only and stop before image mutation.

The refresh phase normally calls
`public.refresh_marketplace_oracle_projections()` with statement timeouts
disabled for the session. If optional helper functions referenced by that
wrapper are absent on the target database, the importer falls back to the
established component refreshes in order: cards from blueprints, card versions,
search candidates, card URLs, token search index, and name ngrams. Any skipped
optional helpers are reported in the JSON output.

After any apply, verify the target cards and derived projections:

```bash
node scripts/oracle-marketplace-migrate.js verify

node scripts/benchmark-searchbar-api.js \
  --base-url https://pokoin.com \
  --endpoint /api/searchbar-cards \
  --runs 1 \
  --queries "mega darkrai ex,giratina,lapras,pikachu" \
  --pool-limit 5000 \
  --timeout-ms 20000 \
  --debug

node scripts/benchmark-searchbar-api.js \
  --base-url https://pokoin.com \
  --endpoint /api/marketplace-autocomplete \
  --runs 1 \
  --queries "mega darkrai ex,giratina,lapras,pikachu" \
  --pool-limit 1000 \
  --timeout-ms 20000 \
  --debug
```

If the API source lacks the requested singles, do not fabricate rows in Oracle.
Record the missing CardTrader expansion/blueprint IDs and wait for CardTrader or
another approved source-of-truth backfill workflow.

### Supabase Name-Index Refresh

Use this only after Oracle projections are healthy. This phase is intentionally
separate from backend implementation so operators can review exactly what
Supabase will contain before it is used in production.

1. Confirm env presence without printing values:

```bash
node -e "for (const k of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_DB_URL','SUPABASE_DB_POOLER_URL','SUPABASE_NAME_INDEX_DATABASE_URL','MARKETPLACE_NAME_SEARCH_DATABASE_URL','MARKETPLACE_DATABASE_URL']) console.log(k, Boolean(process.env[k]))"
```

2. Check whether the table exists through a read-only metadata query. Prefer
   PostgREST/MCP/CLI metadata checks that print only status, row counts, column
   names, and language counts. Do not print DB URLs or API keys.

3. If the table is absent, create it from the standalone SQL or tracked
   migration. This is additive/non-destructive:

```bash
supabase/name-index/002_marketplace_card_name_tokens.sql
# or the tracked migration:
supabase/migrations/20260522173045_marketplace_card_name_tokens.sql
```

The live searchbar helper now reads `public.marketplace_card_name_tokens`, where
each row is one `(language, search_name)` with `card_ids` and lightweight
`representative_labels`. The older `marketplace_card_name_index` card-row cache
can remain for rollback, but it is no longer the production target for name
prediction.

4. Run a dry-run export from Oracle. The script reads Oracle through
   `MARKETPLACE_NAME_SEARCH_DATABASE_URL` when available, otherwise
   `MARKETPLACE_DATABASE_URL`, transforms to the lightweight Supabase shape, and
   prints counts only. Dry-run does not open a Supabase connection and does not
   write rows:

```bash
node scripts/sync-card-name-index-to-supabase.js --languages=en --limit=1000
```

5. Apply only after reviewing dry-run counts, confirming the target database,
   and explicitly deciding to mutate Supabase:

```bash
node scripts/sync-card-name-index-to-supabase.js --apply --full-refresh --languages=en --limit=all
```

For translation-backed name indexes, include fixture-supported languages:

```bash
node scripts/sync-card-name-index-to-supabase.js --apply --full-refresh --languages=en,it,fr,de,es,pt,ja,zh-cn,zh-tw --limit=all
```

Required apply env:

- `MARKETPLACE_NAME_SEARCH_DATABASE_URL` or `MARKETPLACE_DATABASE_URL`
- `SUPABASE_NAME_INDEX_DATABASE_URL` for the Supabase Postgres target, or
  `SUPABASE_DB_URL` when reusing the forum Supabase database for this derived
  table
- `MARKETPLACE_DATABASE_SSL_VERIFY=0` and
  `SUPABASE_NAME_INDEX_DATABASE_SSL_VERIFY=0` unless the local Node runtime
  trusts the database certificates

The script is dry-run by default. Do not pass `--apply` unless the user/operator
explicitly wants to mutate Supabase. Do not use `SUPABASE_URL` or anon keys from
Flutter for this tier; it is backend/script-only and should use a server-side
Postgres/service-role credential.

Incremental apply is intentionally disabled for this unique-name table because
each row must contain the complete card ID list for that name. Use
`--full-refresh` for mutation runs.

6. Verify after apply with row counts only:

```sql
select language, count(*)::integer as rows, max(synced_at) as last_synced_at
from public.marketplace_card_name_tokens
group by language
order by language;
```

For broad-prefix sanity, the English `pik` count should be unique names rather
than per-print rows:

```sql
select count(*)::integer as unique_pik_names
from public.marketplace_card_name_tokens
where language = 'en'
  and (
    compact_name = 'pik'
    or compact_name like 'pik%'
    or 'pik' = any(name_tokens)
  );
```

7. Deploy only after code checks pass, then run the bounded production
   `2pikabench` gate:

```bash
node scripts/benchmark-searchbar-api.js \
  --base-url https://pokoin.com \
  --endpoint /api/searchbar-cards \
  --runs 1 \
  --queries pikac \
  --pool-limit 5000 \
  --timeout-ms 20000 \
  --debug
```

The accepted production run must return HTTP 200 for every prefix, keep visible
rows capped to 20, preserve bounded context IDs/labels, avoid broad primary
fallback for `p`/`pi`, and report payload bytes plus candidate/analytics/rank
timers. When Supabase is live, broad name prefixes may show
`supabase_name_index`; if the table is absent or empty, the path should fall back
to Oracle without failing the endpoint.

Hot blueprint analytics changes must also live in `oracle-postgres/schema/*.sql`.
The current production path is:

- Flutter records bounded card/search context through `/api/marketplace-event`.
- Raw events land in `public.marketplace_card_events`.
- `public.refresh_marketplace_hot_blueprints()` rolls events into
  `public.marketplace_hot_blueprints` with 1h/24h/7d scores.
- Global CardTrader market daily refresh also contributes marketplace signals.
  It calls CardTrader `GET /marketplace/products` with blueprint or expansion
  scope, stores rows in `public.cardtrader_market_listing_snapshots`, archives
  missing rows in `public.cardtrader_market_listing_removed_history`, and
  refreshes `public.cardtrader_blueprint_daily_analytics`. No Pokoin user or
  connected seller is involved. `public.refresh_marketplace_hot_blueprints()`
  folds those signals into `metadata.cardtrader*` fields and adds bounded weight
  to the 24h/7d hot scores.
- `public.get_marketplace_home_snapshot(...)` reads the hot table for Best
  sellers and Featured section IDs. Best sellers are deterministic by score.
  Featured rotates a 12-card window through the top 36 scored rare/promo/variant
  candidates every six hours, so it changes over time without introducing random
  per-request churn.
- `GET /api/marketplace-hot-blueprints?window=1h|24h|7d&limit=50` exposes the
  rollup for debugging/future UI. Use it as an analytics signal, not as settled
  sales volume. CardTrader market removed rows are useful sold/removed signals,
  but they still represent "missing from the global marketplace snapshot" unless
  a future CardTrader order feed confirms the exact sale.

Featured/Best sellers only change after the hot rollup is fresh. If users are
navigating but the homepage stays static, check raw events and rollup freshness
before changing Flutter:

```bash
node - <<'NODE'
const fs = require('fs');
const { Pool } = require('pg');
for (const line of fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const s = line.trim();
  if (!s || s.startsWith('#') || !s.includes('=')) continue;
  const i = s.indexOf('=');
  process.env[s.slice(0, i).replace(/^export\s+/, '').trim()] ||=
    s.slice(i + 1).trim().replace(/^['"]|['"]$/g, '');
}
const pool = new Pool({
  connectionString: process.env.MARKETPLACE_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});
(async () => {
  const status = await pool.query(`
    select
      now() as db_now,
      (select count(*)::int from public.marketplace_card_events where occurred_at >= now() - interval '1 hour') as events_1h,
      (select count(*)::int from public.marketplace_card_events where occurred_at >= now() - interval '24 hours') as events_24h,
      (select max(occurred_at) from public.marketplace_card_events) as last_event_at,
      (select max(refreshed_at) from public.marketplace_hot_blueprints) as hot_refreshed_at,
      (select max(last_event_at) from public.marketplace_hot_blueprints) as hot_last_event_at
  `);
  console.log(status.rows[0]);
})().finally(() => pool.end());
NODE
```

Expected:

- `events_1h`/`events_24h` increase as users view/click cards.
- `hot_refreshed_at` should trail current time by only a few minutes.
- `hot_last_event_at` should be close to `last_event_at`. If raw events are
  fresh but hot rows are old, run
  `select public.refresh_marketplace_hot_blueprints()` and inspect
  `/api/marketplace-event`.

`/api/marketplace-event` and `/api/marketplace-home` opportunistically refresh
the hot rollup when the rollup is older than two minutes. The event path keeps
analytics fresh while users interact; the home path prevents a stale Featured
carousel when traffic is mostly page loads. Keep both paths throttled; do not
refresh on every request without a stale check.

### Firebase User Dimension Sync

Firebase Auth is the source of truth for Pokoin user identity. Oracle keeps a
minimal user dimension so verified `marketplace_card_events.user_uid` values can
be joined to current account state for analytics and personalization:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/sync-firebase-users-to-oracle.js --limit=25
node scripts/sync-firebase-users-to-oracle.js --apply --limit=all
```

The script auto-loads `.env.local`, reads users with Firebase Admin
`listUsers`, defaults to dry-run, and logs counts only. It upserts UID, email,
display name, photo URL, provider IDs, disabled/email verification flags,
Firebase creation/last-sign-in timestamps, and `synced_at` into
`public.marketplace_firebase_users`. It does not store tokens, passwords, or
custom claims.

Verify after apply:

```bash
node - <<'NODE'
const fs = require('fs');
const { Pool } = require('pg');
for (const line of fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const s = line.trim();
  if (!s || s.startsWith('#') || !s.includes('=')) continue;
  const i = s.indexOf('=');
  const key = s.slice(0, i).replace(/^export\s+/, '').trim();
  process.env[key] ||= s.slice(i + 1).trim().replace(/^['"]|['"]$/g, '');
}
const pool = new Pool({
  connectionString: process.env.MARKETPLACE_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});
(async () => {
  const result = await pool.query(`
    select
      count(*)::int as total_users,
      count(*) filter (where disabled)::int as disabled_users,
      count(*) filter (where email_verified)::int as email_verified_users,
      max(synced_at) as last_synced_at
    from public.marketplace_firebase_users
  `);
  console.log(result.rows[0]);
})().finally(() => pool.end());
NODE
```

`/api/marketplace-home` also has a short response/cache layer:

- In-function memory cache: 30 seconds.
- HTTP cache: `max-age=10`, `s-maxage=30`, `stale-while-revalidate=60`.
- SQL Featured rotation: every six hours within the top 36 scored eligible
  candidates.
- Home cards read `homepage_image_url` first. Every marketplace blueprint with
  any source image should have this column populated, preferably with a generated
  CDN/R2 `_homepage.webp` derivative at 240px wide using the source image's
  natural aspect ratio. Product/card metadata can be wrong, so homepage image
  generation must preserve natural aspect and must not rely only on
  `item_kind`/`product_type`.
- If homepage artwork looks degraded, inspect the live
  `/api/marketplace-home` response before tuning image generation. A 500 or a
  payload without `homepageImageUrl` can leave Flutter using cached/fallback
  rows and old `/previews/...` URLs even when the `_homepage.webp` objects are
  healthy.

If Featured appears stuck, first decide which layer is responsible:

```bash
python3 - <<'PY'
import json, time, urllib.request
for i in range(3):
    url = f'https://pokoin.com/api/marketplace-home?_debug={int(time.time()*1000)}_{i}'
    with urllib.request.urlopen(url, timeout=20) as res:
        data = json.loads(res.read().decode())
    print(data.get('generatedAt'), (data.get('sections') or {}).get('featuredIds', [])[:12])
    time.sleep(2)
PY
```

Same IDs inside a cache window are expected. Same IDs across the next six-hour
boundary point to stale deployed SQL/API code, a stale hot rollup, or an
eligible pool smaller than the visible Featured limit.

### Homepage Image Coverage

Use this when preparing or verifying marketplace home images. The target is full
coverage: every `cardtrader_pokemon_blueprints` row with a source image should
have `homepage_image_url` populated. The preferred object is a generated
`_homepage.webp` derivative at 240px wide with natural aspect preserved. If no
full/source image exists but a preview exists, linking the preview is allowed
only as an explicit degraded fallback and should remain visible in verification
counts.

Backfill is idempotent and resumable:

```bash
node scripts/generate-oracle-homepage-card-images.js --verify-coverage
node scripts/generate-oracle-homepage-card-images.js --apply --limit=5000 --concurrency=100
node scripts/generate-oracle-homepage-card-images.js --apply --start-id=<last-next-start-id> --limit=5000 --concurrency=100
```

Use `--limit=all` only after targeted dry-runs and smaller batches are clean.
Stopping an unbounded or long-running apply process leaves partial coverage; run
`--verify-coverage` and record the remaining count before deploy/verification.
The known partial state before the full-coverage backfill was `5,806` populated
rows with `64,215` eligible source rows still missing `homepage_image_url`.
The verifier also checks `get_marketplace_home_snapshot()` output. Treat any
non-zero `snapshot_homepage_mismatches` as incomplete even when table coverage is
`70021/70021`; that means the deployed SQL/API projection is still falling back
to previews.

SQL coverage verification:

```sql
with eligible as (
  select *
  from public.cardtrader_pokemon_blueprints
  where coalesce(preview_image_url, preview_object_key, cdn_image_url, cdn_object_key, image_url, '') <> ''
)
select
  count(*)::int as eligible_blueprints,
  count(*) filter (where coalesce(homepage_image_url, '') <> '')::int as populated_homepage_images,
  count(*) filter (where coalesce(homepage_image_url, '') = '')::int as missing_homepage_images,
  count(*) filter (
    where coalesce(homepage_object_key, homepage_image_url, '') like '%_homepage.webp'
  )::int as generated_homepage_images,
  count(*) filter (
    where coalesce(homepage_image_url, '') <> ''
      and (homepage_object_key = preview_object_key or homepage_image_url = preview_image_url)
  )::int as preview_linked_fallbacks
from eligible;
```

Find remaining gaps:

```sql
select id, name, cdn_object_key, preview_object_key, homepage_object_key, homepage_image_url
from public.cardtrader_pokemon_blueprints
where coalesce(preview_image_url, preview_object_key, cdn_image_url, cdn_object_key, image_url, '') <> ''
  and coalesce(homepage_image_url, '') = ''
order by id asc
limit 50;
```

Sample R2/CDN HEAD checks for generated homepage objects:

```bash
node - <<'NODE' > /tmp/homepage-image-sample-urls.txt
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.MARKETPLACE_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});
(async () => {
  const result = await pool.query(`
    select homepage_image_url
    from public.cardtrader_pokemon_blueprints
    where coalesce(homepage_object_key, homepage_image_url, '') like '%_homepage.webp'
    order by random()
    limit 10
  `);
  for (const row of result.rows) console.log(row.homepage_image_url);
})().finally(() => pool.end());
NODE

while read -r url; do
  curl -L -I "$url" | sed -n '1,8p'
done < /tmp/homepage-image-sample-urls.txt
```

## Blueprint Pricing

Use this section when changing seller listing dimensions, displayed marketplace
prices, card detail market stats, or any future external price importer.

### Purpose

Pokemon prices are dimensional. The same blueprint can have different prices for
condition, language, reverse/holo state, first edition, sealed/signed copies,
graded cards, grading company, grade, and future external source observations.
Do not collapse this into one mutable `price` column.

The current data flow is:

- `public.marketplace_user_listings` stores seller asks and is the source of
  truth for active Pokoin listings.
- `public.marketplace_price_observations` stores append-only raw price facts for
  future external sources such as Cardmarket, TCGplayer, or CardTrader.
- `public.refresh_marketplace_blueprint_price_table(target_card_id)` rebuilds
  dimensional current prices for one blueprint or all blueprints.
- `public.refresh_marketplace_blueprint_price_summary(target_card_id)` rebuilds
  the fast one-row summary consumed by home/search/catalog APIs.
- `GET /api/marketplace-cards` and
  `public.get_marketplace_home_snapshot(...)` read
  `public.marketplace_blueprint_price_summary` instead of doing per-row lateral
  listing aggregation.
- `GET /api/marketplace-blueprint-price?blueprintId=...` is the narrow public
  API for one blueprint's current PKN floor price. It reads the same summary row
  and returns `404` with `price_pkn: null` when no active listing price exists.

### Listing Dimensions

`public.marketplace_user_listings` must keep these collectible dimensions:

- `condition`: current values are `NM`, `SP`, `MP`, `PL`, `Poor`.
- `language`: marketplace language code such as `EN`, `JP`, `IT`, `DE`.
- `reverse`: quick boolean for reverse holo.
- `first_edition`: explicit boolean, default `false`.
- `foil_state`: canonical text state: `standard`, `holo`, `reverse`,
  `stamped`, `promo`, `other`.
- `variant_state`: flexible text for messy Pokemon-specific variants.
- `sealed`, `signed`, `graded`, `grading_company`, `grade`.
- `shipping_available`: fulfillment/shipping availability only.
- `reserve_available`: public Reserve tag for cards available in the Pokoin
  reserve. Keep this separate from shipping. Creating or updating reserve
  listings requires a Firebase reserve role enforced by
  `/api/marketplace-listings`.
- `nft_available`: NFT-backed listing flag; compact UI label is `NFT`.
- `source`: default `pokoin_user_listing`.
- `source_listing_id`: optional external/source-specific identifier.

Flutter listing forms must write the same fields through
`GET|POST|PATCH /api/marketplace-listings`; never add a client-only dimension
that is not persisted in Oracle.

### Price Tables

Keep table responsibilities separate:

- `marketplace_user_listings`: seller asks and availability.
- `marketplace_price_observations`: raw historical facts, append-only.
- `marketplace_blueprint_price_table`: current price rows keyed by blueprint and
  every price dimension. It stores active listing count, listed quantity,
  lowest/highest/average/median ask, observation count, last observed price, and
  source counts.
- `marketplace_blueprint_price_summary`: one row per blueprint for fast UI
  displays. It stores total quantity, active listing count, lowest/median/
  average/highest ask, observation counts, source counts, and refresh time.
- `cardtrader_market_listing_snapshots`: current global CardTrader marketplace
  product rows keyed by `(provider, external_listing_id)`.
- `cardtrader_market_listing_removed_history`: global marketplace rows copied
  before removal. `removed_day` is the previous day by default because the sale
  or removal happened during the last day.
- `cardtrader_user_listing_snapshots`: current per-connected-seller CardTrader
  export rows keyed by `(provider, seller_uid, external_listing_id)`; this is
  separate seller tooling, not homepage/global market analytics.
- `cardtrader_user_listing_removed_history`: missing-from-refresh rows copied
  before removal for connected-seller sync.
- `cardtrader_blueprint_daily_analytics`: day-by-day CardTrader listing/sold
  rollups for homepage ranking and operational checks.

The card detail price graph reads `/api/marketplace-card-sales`. That endpoint
still includes paid Pokoin order items from Firebase, and now also merges Oracle
`marketplace_price_observations` rows with sources `cardtrader_snapshot` and
`cardtrader_removed_sale`.
The daily CardTrader refresh writes:

- `cardtrader_snapshot` observations for current availability/ask history.
- `cardtrader_removed_sale` observations dated to `removed_day`, which makes the
  graph show day-by-day CardTrader-derived sold/removed prices.

Use source filters when diagnosing graphs:

```sql
select observed_at::date, source, count(*), min(price_pkn), avg(price_pkn), max(price_pkn)
from public.marketplace_price_observations
where blueprint_id = 316600
  and source in ('cardtrader_snapshot', 'cardtrader_removed_sale')
group by observed_at::date, source
order by observed_at::date desc, source;
```

### Refresh Rules

Listing writes must refresh only the affected blueprint:

```sql
select public.refresh_marketplace_blueprint_price_summary('316600');
```

`/api/marketplace-listings` is responsible for calling this after create,
update, inactive/remove, and decrement/sold-out writes. The summary function
calls the dimensional table function internally, so API code should call the
summary function only.

Full projection refreshes also rebuild pricing:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
```

`public.refresh_marketplace_oracle_projections()` returns a
`priceSummaries` count. If this count is zero, check whether there are active
listings before assuming failure.

### Diagnostics

Inspect one blueprint:

```bash
node scripts/debug-marketplace-prices.js 316600
```

Expected output includes:

- `summary.listed_quantity`
- `summary.active_listing_count`
- `summary.lowest_ask_pkn`
- `summary.median_ask_pkn`
- `summary.average_ask_pkn`
- `summary.highest_ask_pkn`
- dimensional rows grouped by condition/language/reverse/first edition/foil/
  sealed/signed/graded state.

Find a blueprint with active listings:

```bash
node - <<'NODE'
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const env = path.resolve('.env.local');
if (fs.existsSync(env)) {
  for (const line of fs.readFileSync(env, 'utf8').split(/\r?\n/)) {
    const s = line.trim();
    if (!s || s.startsWith('#') || !s.includes('=')) continue;
    const i = s.indexOf('=');
    const key = s.slice(0, i).replace(/^export\s+/, '').trim();
    let value = s.slice(i + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] ||= value;
  }
}
const pool = new Pool({
  connectionString: process.env.MARKETPLACE_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});
(async () => {
  const result = await pool.query(`
    select card_id, count(*)::int as active_listings
    from public.marketplace_user_listings
    where status = 'active' and quantity_available > 0
    group by card_id
    order by active_listings desc
    limit 10
  `);
  console.log(result.rows);
})().finally(() => pool.end());
NODE
```

Manual verification checklist:

- Same blueprint, same language, different conditions produce separate
  dimensional rows.
- Standard and reverse/foil listings do not merge unless their dimensions match.
- First edition and unlimited listings split into separate rows.
- Graded and raw cards split by `graded`, `grading_company`, and `grade`.
- `inactive`, `paused`, and `sold_out` listings are excluded from active ask
  summaries.
- Home/catalog cards show `price` and `stock` from
  `marketplace_blueprint_price_summary`.

Card palette/type/emoji changes must also live in
`oracle-postgres/schema/*.sql`. `cards_type` stores canonical Pokemon/TCG types
such as `water`, `darkness`, `item`, and `supporter`; `cards_name_type` maps a
card name to one or more types with priority. Use this mapping for species that
can legitimately have multiple types across printings, for example Chien-Pao as
both `water` and `darkness`.

Visible marketplace emojis are stored in the `emoji` column on
`cardtrader_pokemon_blueprints`, `marketplace_cards`,
`marketplace_search_candidates`, and `marketplace_card_versions`. Projection
refreshes compute them with `marketplace_card_emoji(...)`. Name-specific emoji
fixes belong in `marketplace_card_emoji_rules`, seeded by
`marketplace_seed_card_emoji_rules()`, so Flutter and APIs read the same
database-backed symbols.

Artist/illustrator credits live in the separate additive table
`public.marketplace_blueprint_artists`, keyed by `blueprint_id`/`card_id`. Do
not add artist columns to `cardtrader_pokemon_blueprints`, do not mutate
blueprint JSON to store artists, and do not feed artist names into
`marketplace_search_candidates.search_text`, token dimensions, ngrams, rarity
parsing, or ranking. Artist metadata is display attribution only, not
search/ranking intent. Marketplace APIs may left-join this table to expose
`artist` and `illustrator` as display metadata, and artist collection endpoints
may query it by `normalized_artist` for grouping.

Do not fix card palette or emoji exceptions only in Flutter. Persist name/type
rules through `marketplace_seed_cards_name_type()` and name emoji rules through
`marketplace_seed_card_emoji_rules()`, then run a targeted palette/emoji refresh
so projected `card_palette` JSON and `emoji` strings are updated in all
marketplace tables. Example: Cynthia cards intentionally map to the `lightning`
palette, Team Rocket/Dark/Shadow card families should resolve to the dark
palette from the database projection, and Air Balloon should use a balloon/wind
emoji pair instead of the generic card/paw fallback.

### Blueprint Artist Metadata

Use this when enriching cards with illustrator credits. The source of truth is
the separate additive table, not extra columns on the main blueprint table:

```sql
public.marketplace_blueprint_artists
```

Fields:

- `blueprint_id`: primary key and foreign key to
  `public.cardtrader_pokemon_blueprints(id)`.
- `card_id`: generated alias of `blueprint_id` for card-oriented joins.
- `artist` and `illustrator`: display attribution strings. They usually match
  because the current source exposes illustrator credits.
- `normalized_artist`: lowercase normalized lookup key for grouping same-artist
  cards.
- `source`, `source_card_id`, and `source_url`: provenance for the matched
  source record.
- `confidence` and `match_reason`: importer match quality/debug metadata.
- `matched_at`, `raw_metadata`, `created_at`, and `updated_at`: audit/debug
  fields for repeatable imports.

Required rules:

- Apply the schema to peer4 primary only:
  `node scripts/oracle-marketplace-migrate.js schema`.
- Do not write directly to peer3, peer2, or peer1. Physical WAL replication must
  carry the table and rows to replicas.
- Prefer structured sources with explicit illustrator fields. The current source
  is TCGdex `illustrator`; this should remain the first source because it has a
  structured field and clear API provenance.
- Treat `public.marketplace_blueprint_artists` and its known
  `normalized_artist` set as the authority for fallback artist names. TCGdex
  trusted import may follow the existing importer rules, but non-primary
  fallback sources must not introduce new artist authorities.
- Optional local PokemonTCG dataset fallback is supported with
  `--source=pokemon_tcg_data` or `--source=all
  --pokemon-tcg-data-dir=<path>`. Use it only as validation/fill for gaps after
  TCGdex matching, not as a replacement for the primary TCGdex source. Fallback
  artist names are accepted only when their `normalized_artist` already exists in
  `public.marketplace_blueprint_artists`; unknown fallback artists are reported
  as `unknown_artist_not_in_artist_table` and must not be inserted as new artist
  authorities.
- Treat Bulbapedia and PocketMonsters as fallback/reference sources only. They
  can help with set mapping and manual gap analysis, but any future importer path
  may only fill or validate an artist when the normalized name is already present
  in `public.marketplace_blueprint_artists`. Unknown fallback artists must be
  reported as `unknown_artist_not_in_artist_table`, not inserted. Importers also
  must preserve attribution in `source`, `source_url`, `match_reason`, and
  `raw_metadata`, and must account for licensing before copying text or bulk
  data.
- Treat OCR and browser observations as optional debug/reference signals, not as
  ranking input.
- Artist text is not search intent. Extension/browser scraped labels such as
  `Illus.`, `Illustrator:`, or `Artist:` must be stored as artist/debug metadata
  only and must stay out of `rarity`, `variation`, `query`, token dimensions, and
  autocomplete ranking.
- Runtime artist collection reads use `/api/marketplace-artist-cards`, which
  resolves URL slugs against `normalized_artist` and returns card rows from
  `public.marketplace_card_versions` plus `public.marketplace_blueprint_artists`.
  Keep this separate from `/api/marketplace-cards` search so artists remain
  attribution/grouping metadata rather than search intent.
- UI routes built on this table are `/marketplace/{lang}/artists/{artistSlug}`
  and `/collection/artists/{artistSlug}`. The first is a marketplace gallery like
  the versions page; the second is the profile collection view using owned cards
  in color and missing cards dimmed/grayscale.

Manual curation UI:

- `/marketplace/debug/artists` is an admin/debug-only page guarded by the same
  debug profile checks as `/marketplace/debug/refinement`.
- The page calls `GET /api/marketplace-debug-artists` to load one unresolved,
  missing, or low-confidence artist candidate with a large readable
  `cdn_image_url`/`image_url` when available.
- Candidate selection excludes rows already classified as products. It requires
  at least one possible artist from existing `marketplace_blueprint_artists`
  rows for the same conservative Pokémon identity (`canonical_name`), and only
  offers existing normalized artists. It does not introduce unknown artist names
  from fallback sources.
- `POST /api/marketplace-debug-artists` with action `select_artist` upserts
  `marketplace_blueprint_artists` on peer4 with source `manual_debug`,
  confidence `0.99`, provenance in `match_reason`/`raw_metadata`, and refreshes
  the client to the next card.
- Action `classify_product` persists a product override in
  `marketplace_blueprint_classification_overrides` and immediately updates the
  current Oracle projections for that blueprint. A future projection refresh
  must preserve the override. Use this when the displayed image is sealed
  product/box/pack/deck/accessory rather than a single card.
- Action `skip` writes only to `marketplace_artist_debug_skips`; it is a queue
  convenience and not artist metadata.

Importer:

```text
scripts/import-marketplace-blueprint-artists.js
```

Supported operator options:

- `--dry-run`: default mode; matches and reports without writing.
- `--apply`: upserts matched rows into
  `public.marketplace_blueprint_artists`.
- `--limit=<n|all>`: caps candidate blueprints; default is `100`.
- `--batch-size=<n>`: controls upsert batch size; default is `100`.
- `--concurrency=<n>`: caps source lookups; default is `8`.
- `--start-id=<blueprint_id>`: resumes after a previous `nextStartId`.
- `--refresh-existing`: rematches already populated rows.
- `--source=tcgdex|pokemon_tcg_data|all`: selects the source path.
- `--pokemon-tcg-data-dir=<path>`: enables the local fallback dataset.
- `--language=<code>` and `--tcgdex-base-url=<url>`: optional source controls.
- `--report-missing`: read-only diagnostic mode for blueprints without artist
  rows. It scans the same matcher and categorizes misses without upserting.
- `--report-eligible-only`: in report mode, skips obvious metadata/product gaps
  and diagnoses missing card rows that have name, set, and collector number.
- `--write-missing-report=<path>`: writes the missing diagnostic JSON. Prefer
  `workflows/reports/artist-import-missing-YYYYMMDD.json`.
- `--report-sample-size=<n>`: caps stored sample rows per reason; default is
  `8`.

Dry-run a bounded sample before any write:

```bash
node scripts/import-marketplace-blueprint-artists.js \
  --limit=100 \
  --batch-size=100 \
  --concurrency=8
```

Apply a small peer4 sample only after dry-run counts look sane:

```bash
node scripts/import-marketplace-blueprint-artists.js \
  --apply \
  --limit=100 \
  --batch-size=100 \
  --concurrency=8
```

For larger resumable runs, increase gradually and resume from the reported
`nextStartId`:

```bash
node scripts/import-marketplace-blueprint-artists.js \
  --apply \
  --limit=5000 \
  --batch-size=250 \
  --concurrency=16 \
  --start-id=<last-next-start-id>
```

Use `--limit=all` only after a clean sample and no source rate-limit errors.
The script defaults to dry-run, refuses `--apply` against a database in recovery,
skips already-populated rows unless `--refresh-existing` is passed, and logs
matched, ambiguous, not_found, skipped, errors, source counts, reasons, and the
next resume id.

The importer historically did not persist failed-match reasons. Dry-run/apply
runs printed aggregate `reasons` and progress JSON to process output only, while
`public.marketplace_blueprint_artists` stored matched rows. To answer why artist
rows are missing, generate a bounded diagnostic report:

```bash
node scripts/import-marketplace-blueprint-artists.js \
  --report-missing \
  --report-eligible-only \
  --limit=500 \
  --batch-size=100 \
  --concurrency=4 \
  --write-missing-report=workflows/reports/artist-import-missing-YYYYMMDD.json
```

Report mode is read-only and cannot be combined with `--apply`. It includes
overall table coverage, scanned counts, canonical reason counts, raw matcher
reason counts, and small sample rows per reason. Canonical reasons include
`set_not_found`, `card_not_found`, `missing_illustrator`, `ambiguous_set`,
`ambiguous_card`, `low_confidence`, `source_error`, `skipped_existing`,
`unknown_artist_not_in_artist_table`, `non_card_product`, and metadata skips such
as `missing_collector_number`.
Use low `--concurrency` and bounded `--limit` when diagnosing against remote
sources; use `--limit=all` only if source traffic is acceptable.

Current applied status as of 2026-05-22:

- Schema was applied on peer4 through the normal schema workflow.
- Peer3 replicated the table and rows through physical WAL streaming.
- `18,115` artist rows were populated.
- `372` distinct normalized artists were present.
- Peer2 and peer1 were not verified because the replica env files were missing
  in the operator environment at verification time.
- Remaining gaps need set mapping and fallback-source work, especially where
  CardTrader/TCGdex set names or collector numbers do not line up directly.

Verification queries:

```sql
select
  count(*)::int as artist_rows,
  count(*) filter (where source = 'tcgdex')::int as tcgdex_rows,
  count(distinct normalized_artist)::int as distinct_artists,
  max(matched_at) as last_matched_at
from public.marketplace_blueprint_artists;

select a.blueprint_id, c.name, c.set_name, c.card_number, a.artist, a.source, a.confidence
from public.marketplace_blueprint_artists a
join public.marketplace_search_candidates c on c.card_id = a.blueprint_id
order by a.matched_at desc
limit 25;

select
  a.blueprint_id,
  c.name,
  c.set_name,
  c.card_number,
  a.artist,
  a.normalized_artist,
  a.source,
  a.confidence
from public.marketplace_blueprint_artists a
left join public.marketplace_search_candidates c on c.card_id = a.blueprint_id
where a.blueprint_id = 118502;

select
  count(*)::int as same_artist_blueprints
from public.marketplace_blueprint_artists
where normalized_artist = (
  select normalized_artist
  from public.marketplace_blueprint_artists
  where blueprint_id = 118502
);

select
  a.blueprint_id,
  c.name,
  c.set_name,
  c.card_number,
  a.artist
from public.marketplace_blueprint_artists a
left join public.marketplace_search_candidates c on c.card_id = a.blueprint_id
where a.normalized_artist = 'ryo ueda'
order by c.set_name, c.card_number, a.blueprint_id
limit 50;
```

Blueprint `118502` verified as `Ryo Ueda`, and the same normalized artist lookup
returned `360` matched blueprints.

### Artist Profile Enrichment

Use this when adding sourced artist biographies, profile pictures, or reference
links for public artist pages. Store this metadata separately from card
attribution rows:

```sql
public.marketplace_artist_profiles
```

Fields include `normalized_artist`, `display_name`, `summary`, `bio`,
`profile_image_url`, `profile_image_cdn_url`, `profile_image_object_key`,
`pocketmonsters_url`, `pocketmonsters_id`, `bulbapedia_url`,
`bulbapedia_title`, `source_name`, `source_url`, `source_attribution`,
`fetched_at`, `raw_metadata`, and timestamps.

Source rules:

- `public.marketplace_blueprint_artists.normalized_artist` remains the authority
  for which artists can receive a profile. PocketMonsters, Bulbapedia, Wikidata,
  or other fallback sources must not create new artist authorities.
- Artist display aliases are profile/API/UI metadata only. If a known artist needs
  a public label that differs from its stored `normalized_artist`, prefer
  `public.marketplace_artist_profiles.display_name` or a narrow API display
  override, and preserve existing slug compatibility. For example,
  `2017 pikachu project` / `pikachu project 2017` should display as
  `Pikachu Project`, while existing normalized keys and legacy slugs continue to
  resolve.
- PocketMonsters staff pages can provide staff profile pictures and biography
  text. Prefer caching the image into Pokoin R2/CDN and storing both source and
  CDN/object-key fields. If R2 credentials or public URL config are missing, keep
  the source URL and report `cache_needed` without failing the profile import.
  Artist profile images use the same `cardvault-images` R2 bucket as card
  images, under `artist-profiles/<artist-slug>.<ext>`. Store the public URL as
  the same-origin Worker proxy path (`https://pokoin.com/card-images/artist-profiles/...`)
  unless `R2_ARTIST_PROFILE_IMAGES_PUBLIC_URL` or
  `POKOIN_ARTIST_PROFILE_IMAGES_PUBLIC_URL` explicitly overrides it; direct
  `https://cdn.pokoin.com/...` requests can be preempted by zone security before
  the image Worker runs.
- Bulbapedia can provide additional short summary/reference context for every
  known artist in `public.marketplace_blueprint_artists`, but only when the page
  title exactly matches the normalized artist after cleanup. The importer checks
  likely titles such as `<Artist>`, `<Artist>_(TCG_Illustrator)`, and
  `<Artist>_(illustrator)` through the MediaWiki API, stores only the concise
  lead extract, `bulbapedia_url`, `bulbapedia_title`, and attribution in
  `source_attribution`, then displays the Bulbapedia source link and CC
  BY-NC-SA reference on the artist page.
- Ambiguous, fuzzy, or missing source matches must be reported, not inserted.
  Never copy broad scraped content when the source page identity is uncertain.
- Artist profile text is display metadata only. Do not join it into
  `marketplace_search_candidates.search_text`, token dimensions, ngrams,
  autocomplete ranking, hot scoring, or card identity projections.

Importer:

```text
scripts/import-marketplace-artist-profiles.js
```

Supported operator options:

- `--dry-run`: default mode; fetches/matches and reports without writing.
- `--apply`: upserts verified rows into `public.marketplace_artist_profiles`.
- `--limit=<n|all>`: caps artists; default is `100`.
- `--concurrency=<n>`: caps source lookups; keep low for public sources.
- `--artist=<name>`: restricts to one or a comma-separated set of existing
  normalized artist names.
- `--source=all|pocketmonsters|bulbapedia|wikidata`: selects enrichment sources.
- `--pocketmonsters-id=<id>` or `--pocketmonsters-url=<url>`: targeted staff-page
  import for a manually verified PocketMonsters profile such as `7159`.
- `--write-report=<path>`: writes a JSON report. Prefer
  `workflows/reports/artist-profile-import-YYYYMMDD.json`.
- `--refresh-existing`: refreshes artists that already have profile rows.
- `--no-cache-images`: skips R2/CDN image caching even when credentials exist.
- `--audit-image-cache`: reports profile rows that have a source image but are
  missing `profile_image_cdn_url` or `profile_image_object_key`.
- `--recache-missing-images`: uses already verified profile rows and only
  recaches missing image objects/fields. It does not discover new source pages.

Dry-run a controlled target before applying:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --source=pocketmonsters \
  --pocketmonsters-id=7159 \
  --artist="<verified artist name>" \
  --limit=1 \
  --write-report=workflows/reports/artist-profile-7159-dry-run.json
```

Apply only after the dry-run shows an exact existing artist-table match:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --apply \
  --source=pocketmonsters \
  --pocketmonsters-id=6956 \
  --artist="Mitsuhiro Arita" \
  --limit=1 \
  --concurrency=1
```

For small mixed-source batches:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --source=all \
  --limit=10 \
  --concurrency=1 \
  --write-report=workflows/reports/artist-profile-import-sample.json
```

Use `--limit=all` only after several clean bounded runs and no source
rate-limit/ambiguity issues. Do not mass-fetch public sources aggressively.

For all-artist Bulbapedia enrichment, start with a dry run over the existing
artist authority table and inspect `counts.reasons` plus the skipped report rows
before applying:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --source=bulbapedia \
  --limit=all \
  --concurrency=1 \
  --write-report=workflows/reports/artist-profile-bulbapedia-all-dry-run-YYYYMMDD.json
```

If the dry run only shows expected `missing_page`, `title_mismatch`,
`empty_extract`, or `non_artist_extract` skips, apply with the same conservative
concurrency:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --apply \
  --source=bulbapedia \
  --limit=all \
  --concurrency=1 \
  --write-report=workflows/reports/artist-profile-bulbapedia-all-apply-YYYYMMDD.json
```

Verification:

```sql
select
  count(*)::int as profile_rows,
  count(*) filter (where profile_image_cdn_url <> '')::int as cached_images,
  count(*) filter (where profile_image_url <> '' and profile_image_cdn_url = '')::int as cache_needed,
  count(*) filter (where pocketmonsters_url <> '')::int as pocketmonsters_rows,
  count(*) filter (where bulbapedia_url <> '')::int as bulbapedia_rows,
  max(updated_at) as last_updated_at
from public.marketplace_artist_profiles;

select normalized_artist, display_name, pocketmonsters_url, bulbapedia_url,
       profile_image_cdn_url, profile_image_url, source_attribution
from public.marketplace_artist_profiles
where normalized_artist = '<normalized artist>'
limit 1;
```

Profile-image coverage audit:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --audit-image-cache \
  --limit=all \
  --write-report=workflows/reports/artist-profile-image-cache-audit-YYYYMMDD.json
```

Rows with `profile_image_url` but empty `profile_image_cdn_url` or
`profile_image_object_key` already have a verified source image but still need
R2 caching. Re-cache those rows without rediscovering source pages:

Quality audit:

Cached image coverage does not prove the image is useful. After bulk recaches,
sample or audit cached `artist-profiles/*` objects with image metrics before
calling the image work complete. Flag source-backed images that are tiny,
mostly grayscale/low-saturation, near-blank, mostly transparent, or repeated
across many artists. A common PocketMonsters placeholder is a 250x250,
311-byte grayscale PNG reused by many staff pages; do not present it as a real
artist portrait. If the cached bytes match the source placeholder and no better
verified source exists, keep the source/profile text but clear or suppress the
cached image only after review so the UI falls back to initials.

Write quality-audit output under
`workflows/reports/artist-profile-grey-placeholder-audit-YYYYMMDD.json` with
counts, affected artist slugs, source-image comparison, and recommended action
(`recache_from_verified_source` or `clear_image_fields_after_review`).

Fallback card-art avatars:

When an authority artist has no profile image, or the quality audit marks the
cached image as a placeholder/low-value image, generate a square avatar from a
card they illustrated instead of showing the grey PocketMonsters placeholder.
Do not overwrite real human portraits. Use:

```text
scripts/generate-artist-fallback-avatars.js
```

Selection and crop rules:

- Target only artists in the placeholder audit or rows where
  `profile_image_url`, `profile_image_cdn_url`, and `profile_image_object_key`
  are all empty.
- Prefer cards by rarity/category: illustration cards first (`Special
  Illustration Rare`, `Illustration Rare`, `Special Art Rare`, `Art Rare`,
  character rares), then full-art/alternate-art/ultra/secret art, then normal
  art.
- Use full-size `cdn_image_url`/`image_url` sources, not `preview_image_url` or
  generated homepage crops.
- Crop a square from top-center (`x` centered, `y` about 10% down, clamped to
  image bounds), resize to 512x512 PNG, and upload to
  `artist-profiles/generated/<artist-slug>.png`.
- Store provenance in `source_attribution.generatedProfileImage` and
  `raw_metadata.generatedProfileImage`: source card/blueprint ids, rarity,
  source image URL/object key, generation reason, crop strategy, and
  `generatedAt`.

Operator flow:

```bash
node scripts/generate-artist-fallback-avatars.js \
  --artist="Aky CG Works" \
  --write-report=workflows/reports/artist-fallback-avatar-dry-run-YYYYMMDD-sample.json

node scripts/generate-artist-fallback-avatars.js \
  --apply \
  --artist="Aky CG Works" \
  --concurrency=1 \
  --write-report=workflows/reports/artist-fallback-avatar-apply-YYYYMMDD-sample.json

node scripts/generate-artist-fallback-avatars.js \
  --apply \
  --limit=all \
  --concurrency=2 \
  --write-report=workflows/reports/artist-fallback-avatar-apply-YYYYMMDD-full.json
```

```bash
node scripts/import-marketplace-artist-profiles.js \
  --recache-missing-images \
  --limit=all \
  --concurrency=1 \
  --write-report=workflows/reports/artist-profile-image-recache-dry-run-YYYYMMDD.json

node scripts/import-marketplace-artist-profiles.js \
  --apply \
  --recache-missing-images \
  --limit=all \
  --concurrency=1 \
  --write-report=workflows/reports/artist-profile-image-recache-apply-YYYYMMDD.json
```

For a single verified cache miss, keep the run targeted:

```bash
node scripts/import-marketplace-artist-profiles.js \
  --apply \
  --recache-missing-images \
  --artist="Mitsuhiro Arita" \
  --limit=1 \
  --concurrency=1
```

Runtime reads:

- `/api/marketplace-artist-cards` left-joins
  `public.marketplace_artist_profiles` and returns a `profile` object with CDN
  image, source image, PocketMonsters, and Bulbapedia fields.
- `/marketplace/{lang}/artists/{artistSlug}/profile` displays the profile image,
  source links, and Bulbapedia attribution when available, with initials fallback
  when missing.

After a schema/apply run, verify physical replicas from `pokoinpos`:

Artist image CDN verification:

```bash
wrangler r2 object get "cardvault-images/artist-profiles/<artist-slug>.png" --remote --file /tmp/artist-profile.png
curl -L -I -A "Mozilla/5.0" "https://pokoin.com/card-images/artist-profiles/<artist-slug>.png"
curl -L -I -A "Mozilla/5.0" "https://pokoin.com/card-images/<known-card-image>"
```

The successful response should include `200`, the image `content-type`,
`access-control-allow-origin: *`, and `x-pokoin-cdn-worker: r2-card-images`.

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer3-postgres-replica.env
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer2-postgres-replica.env
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer1-postgres-replica.env
```

### Blueprint TCGdex Metadata

Use this when enriching marketplace blueprints with structured TCG metadata from
TCGdex. The source of truth is a separate additive table, not extra columns on
`cardtrader_pokemon_blueprints`:

```sql
public.marketplace_blueprint_tcg_metadata
```

Fields:

- `blueprint_id`: primary key and foreign key to
  `public.cardtrader_pokemon_blueprints(id)`.
- `card_id`: generated alias of `blueprint_id` for card-oriented joins.
- Scalar metadata: `category`, `set_id`, `set_name`, `set_logo_url`,
  `set_symbol_url`, `set_official_card_count`, `set_total_card_count`, `hp`,
  `stage`, `evolve_from`, `retreat`, `description`, `flavor_text`,
  `regulation_mark`, and `source_updated_at`.
- JSONB metadata: `set_metadata`, `variants`, `types`, `attacks`, `abilities`,
  `weaknesses`, `resistances`, `legal`, and `raw_metadata`.
- Provenance and audit fields: `source`, `source_card_id`, `source_url`,
  `confidence`, `match_reason`, `matched_at`, `created_at`, and `updated_at`.

Required rules:

- Apply the schema and data to peer4 primary only:
  `node scripts/oracle-marketplace-migrate.js schema`.
- Do not write directly to peer3, peer2, or peer1. Physical WAL replication must
  carry the table and rows to replicas.
- Keep artist/illustrator credits in
  `public.marketplace_blueprint_artists`. TCGdex `illustrator` may appear only
  inside `raw_metadata` for provenance/debugging.
- TCGdex metadata is enrichment/display metadata. Do not feed it into
  `marketplace_search_candidates`, token dimensions, autocomplete ranking,
  hot-score ranking, or marketplace identity unless a future search feature
  explicitly designs that behavior.
- Prefer set/card-list matching locally. The importer downloads TCGdex sets,
  fetches set details once per set through an in-process cache, and rate-limits
  card detail requests even when `--concurrency` is high.

Importer:

```text
scripts/import-marketplace-blueprint-tcgdex-metadata.js
```

Supported operator options:

- `--dry-run`: default mode; matches and reports without writing.
- `--apply`: upserts matched rows into
  `public.marketplace_blueprint_tcg_metadata`.
- `--limit=<n|all>`: caps candidate blueprints; default is `100`.
- `--batch-size=<n>`: controls upsert batch size; default is `100`.
- `--concurrency=<n>`: caps local matching work; remote TCGdex requests are
  additionally capped internally.
- `--start-id=<blueprint_id>`: resumes after a previous `nextStartId`.
- `--refresh-existing`: rematches already populated rows.
- `--language=<code>` and `--tcgdex-base-url=<url>`: optional source controls.
- `--tcgdex-min-interval-ms=<n>`: minimum delay between remote TCGdex requests;
  default is conservative.
- `--report-missing`: read-only diagnostic mode for blueprints without metadata.
- `--write-missing-report=<path>`: writes the missing diagnostic JSON. Prefer
  `workflows/reports/tcgdex-metadata-missing-YYYYMMDD.json`.
- `--report-sample-size=<n>`: caps stored sample rows per reason; default is `8`.

Dry-run a bounded sample before any write:

```bash
node scripts/import-marketplace-blueprint-tcgdex-metadata.js \
  --limit=100 \
  --batch-size=100 \
  --concurrency=4
```

Apply a small peer4 sample only after dry-run counts look sane:

```bash
node scripts/import-marketplace-blueprint-tcgdex-metadata.js \
  --apply \
  --limit=100 \
  --batch-size=100 \
  --concurrency=4
```

For larger resumable runs, increase gradually and resume from the reported
`nextStartId`:

```bash
node scripts/import-marketplace-blueprint-tcgdex-metadata.js \
  --apply \
  --limit=5000 \
  --batch-size=250 \
  --concurrency=6 \
  --start-id=<last-next-start-id>
```

Use `--limit=all` only after a clean sample and no source rate-limit errors. The
script defaults to dry-run, refuses `--apply` against a database in recovery,
skips already-populated rows unless `--refresh-existing` is passed, and logs
`matched`, `inserted`, `updated`, `skipped`, `ambiguous_set`,
`set_not_found`, `card_not_found`, `low_confidence`, `missing_field`,
`errors`, reason counts, and the next resume id.

Generate a bounded missing report:

```bash
node scripts/import-marketplace-blueprint-tcgdex-metadata.js \
  --report-missing \
  --limit=500 \
  --batch-size=100 \
  --concurrency=4 \
  --write-missing-report=workflows/reports/tcgdex-metadata-missing-YYYYMMDD.json
```

Report mode is read-only and cannot be combined with `--apply`. It includes
overall table coverage, scanned counts, canonical reason counts, raw matcher
reason counts, and small sample rows per reason.

Verification queries:

```sql
select
  count(*)::int as metadata_rows,
  count(*) filter (where source = 'tcgdex')::int as tcgdex_rows,
  count(*) filter (where category = 'Pokemon')::int as pokemon_rows,
  count(*) filter (where category = 'Trainer')::int as trainer_rows,
  count(*) filter (where category = 'Energy')::int as energy_rows,
  count(distinct set_id)::int as distinct_sets,
  max(matched_at) as last_matched_at,
  max(source_updated_at) as latest_source_updated_at
from public.marketplace_blueprint_tcg_metadata;

select
  m.blueprint_id,
  c.name,
  c.set_name,
  c.card_number,
  m.category,
  m.types,
  m.hp,
  m.regulation_mark,
  m.confidence
from public.marketplace_blueprint_tcg_metadata m
left join public.marketplace_search_candidates c on c.card_id = m.blueprint_id
order by m.matched_at desc
limit 25;

select
  category,
  regulation_mark,
  count(*)::int as rows
from public.marketplace_blueprint_tcg_metadata
group by category, regulation_mark
order by rows desc, category, regulation_mark;
```

After a schema/apply run, verify physical replicas from `pokoinpos`:

```bash
cd /Users/giuseppe/pokoinpos
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer3-postgres-replica.env
```

If peer2/peer1 variation replicas are configured, verify them as well. If their
env files are missing or the replicas are not provisioned, document that they
could not be verified and do not write to them directly.

Current applied status as of 2026-05-22:

- Schema was applied on peer4 with additive DDL for
  `public.marketplace_blueprint_tcg_metadata`.
- A controlled dry-run from `--start-id=109848 --limit=100` matched `89/100`
  rows with no TCGdex/API errors.
- A controlled sample apply inserted `89` rows, then bounded follow-up applies
  inserted `667` and `4,058` rows.
- Peer4 currently has `4,814` TCGdex metadata rows from `44` TCGdex sets:
  `4,012` Pokemon, `652` Trainer, and `150` Energy rows.
- Eligible marketplace blueprints remaining without TCGdex metadata: `59,497`.
  Additional non-eligible gaps include `6,103` non-card/product rows and `4,554`
  rows missing collector numbers.
- The latest resume point from the bounded apply is `--start-id=120063`; a
  post-import missing report covering the next 500 rows wrote
  `workflows/reports/tcgdex-metadata-missing-after-120063-20260522.json`.
- Peer3 was verified through a direct read-only query using the peer3 env file:
  `pg_is_in_recovery() = true`, the metadata table exists, and row count is
  `4,814`.
- The Docker-based replication status script could not run in the local
  operator environment because Docker was unavailable. The direct peer3 query
  verified replicated table/count state, but sender/slot health still needs the
  normal `postgres-replication-status.sh` check from a Docker-capable host.
- Peer2 and peer1 were not verified because `peer2-postgres-replica.env` and
  `peer1-postgres-replica.env` were missing in the operator environment.

## Backfill Missing Card Palettes

When many marketplace cards render with the grey fallback, check whether their
Oracle rows have `card_palette->>'key' = 'fallback'`. Most misses come from
CardTrader rows whose `card_type` is only `Trading card`.

Use the repeatable classifier to enrich `cards_name_type`, seed emoji rules, and
propagate palette JSON plus emoji strings into the projected marketplace tables:

```bash
node scripts/backfill-marketplace-card-palettes.js
node scripts/backfill-marketplace-card-palettes.js --apply --refresh
```

The script reads the peer4 Oracle env from
`/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env` by default. It also
creates the `cards_name_type_lower_name_idx` lookup index if missing, because
`marketplace_name_palette_key()` resolves names case-insensitively.
In `--apply` mode it first runs `marketplace_seed_cards_name_type()` so schema
seed rules are applied before palette JSON is refreshed. Schema apply also
creates `marketplace_card_emoji_rules`; keep obvious item/supporter emoji
exceptions there instead of adding client-side hardcoding.

The default `--refresh` path intentionally performs a targeted palette-only
propagation into:

- `cardtrader_pokemon_blueprints`
- `marketplace_cards`
- `marketplace_search_candidates`
- `marketplace_card_versions`

The targeted refresh includes both `palette-backfill%` mappings, schema
`seed-rule` mappings, and names in `marketplace_card_emoji_rules`, so it is
appropriate for small permanent palette/emoji exceptions such as Cynthia, Team
Rocket/Dark/Shadow families, Air Balloon, and obvious item/supporter cards.

Use `--full-refresh` only when non-palette projection logic changed. The full
projection rebuild can be much slower because it recomputes the complete
marketplace card projection, not just palette JSON.

Validation query:

```sql
select coalesce(card_palette->>'key', '') as key, count(*)::int as count
from public.marketplace_search_candidates
where item_kind = 'single' and product_type = 'card'
group by 1
order by count desc, key;
```

Emoji validation query:

```sql
select card_id, name, card_palette->>'key' as palette_key, emoji
from public.marketplace_search_candidates
where lower(name) in (
  'air balloon',
  'rare candy',
  'professor''s research',
  'battle vip pass',
  'volkner'
)
order by name, card_id
limit 50;
```

After the 2026-05-19 backfill, single-card fallback rows dropped from `42,859`
to `4,145`. Remaining high-volume misses include names such as `Meloetta`,
`Eiscue`, `Squawkabilly ex`, `Urshifu`, `Bede`, `Artazon`, and other trainer or
form-specific cases that should be handled with deliberate manual rules rather
than blind classification.

## Deploy Web/API

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. It can publish an
incomplete output. The deploy script also copies `_marketplace_db.js` and rewrites
marketplace API imports for the Vercel output layout. Autocomplete/searchbar code
now also depends on the optional Supabase name-index helper; ensure `_supabase.js`
is copied/rewritten with the marketplace API bundle or kept behind a safe lazy
optional import. If production logs show `Cannot find module './_supabase'` from
`/api/marketplace-autocomplete.js`, the deployed bundle is stale/incomplete and
backend `2pikabench` results are invalid until redeployed with the helper.

Before deploying a database-related change, confirm Vercel points at the current
writable primary:

- Normal state: `MARKETPLACE_DATABASE_URL` points to peer4.
- After failover: `MARKETPLACE_DATABASE_URL` points to promoted peer3.
- `MARKETPLACE_NAME_SEARCH_DATABASE_URL` or `MARKETPLACE_PEER3_DATABASE_URL`
  points to peer3 for name/predictive reads.
- `MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` or `MARKETPLACE_PEER2_DATABASE_URL`
  plus `MARKETPLACE_PEER1_DATABASE_URL` points to peer2/peer1 for
  dimension/fanout reads.
- `MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS` points to peer2/peer1/peer3 for
  autocomplete ranking analytics. It should not point only at peer4.

Do not deploy APIs against a standby database URL.

Competitive marketplace deploys have an additional data gate: confirm
`oracle-postgres/schema/014_limitless_competitive.sql` has been applied to the
writable primary and `scripts/sync-limitless-competitive.js --apply` has loaded
public Limitless data before treating `/marketplace/competitive` as live. If that
data is not intentionally ready, do not ship the frontend-only route as a
completed feature.

## Guarded Supabase Cleanup

Only run cleanup after Oracle is loaded, Vercel has `MARKETPLACE_DATABASE_URL`,
and production marketplace APIs have been verified.

Dry checks before cleanup:

```bash
node scripts/oracle-marketplace-migrate.js verify
rg "rest/v1/(marketplace|cardtrader)|rpc/search_marketplace|_supabaseUrl|_supabaseAnonKey" lib api
```

Expected:

- Oracle verify returns rows for `porygon`, `piachu 151`, and `char ex`.
- Runtime code has no Supabase marketplace/cardtrader references.
- Forum APIs still reference `_supabase`.

Destructive cleanup command:

```bash
CONFIRM_DROP_SUPABASE_MARKETPLACE=drop-marketplace \
  node scripts/supabase-cleanup-marketplace.js
```

The script refuses to run unless:

- `SUPABASE_DB_URL` is set.
- `MARKETPLACE_DATABASE_URL` is set.
- Oracle has non-empty `marketplace_search_candidates`.
- Oracle has non-empty `marketplace_card_versions`.
- Supabase forum tables exist.

The cleanup SQL is in:

```bash
supabase/cleanup/20260519_drop_marketplace_after_oracle_cutover.sql
```

It drops old marketplace/catalog/search tables and functions from Supabase while
keeping `forum_*` objects.

## Verification

```bash
node --test api/marketplace-autocomplete.test.js
node --test api/_marketplace_db.test.js
node --test api/marketplace-search-candidates.test.js
node --check api/_marketplace_db.js
node --check api/marketplace-cards.js
node --check api/marketplace-card-versions.js
node --check api/marketplace-search-candidates.js
node --check scripts/sync-card-name-index-to-supabase.js
node --test scripts/sync-card-name-index-to-supabase.test.js
node --check scripts/oracle-marketplace-migrate.js
node --check scripts/supabase-cleanup-marketplace.js
flutter analyze lib/services/card_service.dart
flutter test test/card_service_test.dart
```

Database replication verification, from the `pokoinpos` repo:

```bash
deploy/scripts/postgres-replication-status.sh \
  deploy/env/peer4-postgres.env \
  deploy/env/peer3-postgres-replica.env
```

Healthy output should show peer4 with an active replication sender and peer3
with `pg_is_in_recovery()` true. If peer3 has been promoted, use the promoted
peer3 runbook before making more database changes.

For variation replicas, run the same check with `peer2-postgres-replica.env` and
`peer1-postgres-replica.env`. Healthy output should show active peer2/peer1
replication slots/senders on peer4 and each replica in recovery. Do not add
`MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` to production until this is true.

After deploy:

```bash
curl -s https://pokoin.com/api/marketplace-home | python3 -m json.tool | sed -n '1,40p'
```

Then verify user flows:

- `/marketplace` home loads cards and sections.
- `https://api.pokoin.com/healthz` is healthy before frontend promotion.
- `https://api.pokoin.com/api/marketplace-competitive` returns a non-empty
  Limitless competitive payload after schema and sync.
- `/marketplace/competitive` shows visible competitive data and its trophy icon
  navigation route is visible.
- `/marketplace/search?q=porygon` shows multiple matching cards.
- Generated share/detail URLs use canonical public-number marketplace paths, for
  example `/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions`.
- Legacy numeric card URLs such as `/marketplace/en/cards/316600` and
  `/marketplace/en/cards/316600-leafeon-005-131-prismatic-evolutions` still load
  and canonicalize to the public-number URL after resolution.
- Digit-only root short links such as `/129834` redirect through
  `/marketplace/en/cards/129834`; non-numeric root paths such as `/wallet`,
  `/leafeon`, and `/129834-leafeon` are not intercepted.
- Autocomplete handles `piachu 151`, `char ex`, `v`, `darkrai v`,
  `azief lv x`, and `mew special illustration rare`.
- `v` returns actual `... V` cards, `darkrai v` ranks `Darkrai V` first, and
  `azief lv x` ranks `Azelf LV.X`.
- `/card/:id` previous/next stays within the expansion.
- `/forum` still reads and writes through Supabase.

## Rules

- Do not add new marketplace tables/functions to Supabase except the derived
  `marketplace_card_name_tokens` name-search cache documented above.
- Do not add new client-side Supabase marketplace reads.
- Do not delete Supabase forum tables.
- Do not run cleanup without a verified Oracle load and a backup.
