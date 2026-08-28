# CardTrader Inventory Sync Workflow

## Current Vertical Slice

Pokoin supports a production-safe seller connection flow at:

```text
/marketplace/connect
```

Treat this page as seller tooling owned by the authenticated profile/seller
area. It can be reached from `/profile`, `/inventory`, or contextual seller
management links, but it should not be promoted as a global top-bar `Sell`
action. The marketplace top bar stays reserved for search/navigation, wallet,
cart, and profile/sign-in on both desktop and mobile.

The page lets a signed-in seller paste a CardTrader API token. The token is sent
once to Pokoin's server API, validated against CardTrader, encrypted, and stored
server-side. The Flutter client receives only connection status and safe
CardTrader metadata; it never receives the raw token after submission.

## Required Env

Set this only in the trusted server environment:

```text
CARDTRADER_TOKEN_ENCRYPTION_KEY
```

The value must decode to exactly 32 bytes. Supported forms:

- 64 hex characters.
- Base64 encoding of 32 random bytes.
- A raw 32-byte UTF-8 string.

Generate a base64 key locally:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('base64'))"
```

If the env var is missing or invalid, CardTrader connect/import APIs return a
JSON configuration error and do not store secrets.

Vercel production compatibility routes that call CardTrader live listing APIs
also require a global CardTrader token in Vercel production:

```text
CARDTRADER_AUTH_TOKEN # or CARDTRADER_API_TOKEN
```

This token is separate from encrypted per-seller tokens and must never be exposed
to Flutter/client builds.

## Firestore Storage

Seller CardTrader state is stored in:

```text
seller_integrations/{firebaseUid}__cardtrader
```

Stored fields include:

- `uid`
- `provider: "cardtrader"`
- `enabled`
- `metadata`: safe app/user/seller/scopes returned by `GET /info`
- `encryptedToken`: AES-256-GCM envelope
- `encryptedSharedSecret`: AES-256-GCM envelope for CardTrader webhook shared secret
- `connectedAt`, `lastValidatedAt`, `updatedAt`, `disconnectedAt`

Do not store plaintext CardTrader tokens or shared secrets. Do not expose
`encryptedToken`, `encryptedSharedSecret`, raw token, or raw shared secret to
Flutter.

## API Flow

Connect:

```text
POST /api/cardtrader-connect
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Request:

```json
{ "token": "<cardtrader-token>" }
```

Server behavior:

1. Verifies the Firebase bearer token.
2. Validates `CARDTRADER_TOKEN_ENCRYPTION_KEY`.
3. Calls `GET https://api.cardtrader.com/api/v2/info` with
   `Authorization: Bearer <token>`.
4. Encrypts the CardTrader token and returned `shared_secret`.
5. Stores/updates the seller integration document.
6. Returns safe connection status only.

Status:

```text
GET /api/cardtrader-status
Authorization: Bearer <pokoin-bearer-token>
```

Disconnect:

```text
POST /api/cardtrader-disconnect
DELETE /api/cardtrader-connect
Authorization: Bearer <pokoin-bearer-token>
```

Disconnect disables the integration and removes encrypted secret envelopes from
the active document.

Clean linked listings:

```text
POST /api/cardtrader-clean-listings
Authorization: Bearer <pokoin-bearer-token>
```

This is an explicit confirmed seller action in `/marketplace/connect`. It
inactivates only listings owned by the current Firebase UID whose `source` or
`source_listing_id` indicates CardTrader linkage. It must not touch native Pokoin
listings, even when the seller is the same user. After cleanup, refresh affected
marketplace price summaries.

Dry-run import:

```text
POST /api/cardtrader-import-dry-run
Authorization: Bearer <pokoin-bearer-token>
```

This decrypts the token server-side, calls `GET /products/export`, and returns a
count plus a small redacted sample. It does not write Pokoin listings and does
not call CardTrader create/update/delete/increment endpoints.

Global daily market listing snapshot refresh:

```text
Oracle/peer4 scheduled job or script
```

The global CardTrader market-data ingestion schedule is owned by the Oracle
host connected to the peer4 marketplace primary. It is not a Vercel Cron. The
scheduled Oracle wrapper first uses the global CardTrader app/API token to call
CardTrader `GET /marketplace/products` by blueprint or expansion and refresh
Oracle global marketplace listing snapshots. After that import succeeds, it runs
the separate homepage/catalog projection refresh. No Firebase user, connected
Pokoin seller, or encrypted seller token is involved.

Vercel functions may serve read APIs and explicit manual diagnostics only. They
must not own the daily CardTrader schedule, retry loop, or production ingestion
cadence. If a compatibility endpoint such as
`GET|POST /api/cardtrader-daily-listings-refresh` remains during rollout, treat
it as manual/admin diagnostics only; do not wire it to Vercel Cron. Keep
`vercel.json` free of a `crons` entry for this endpoint. Any Vercel
compatibility route that calls CardTrader live, including card-page live
listings, requires `CARDTRADER_AUTH_TOKEN` or `CARDTRADER_API_TOKEN` in Vercel
production.

Optional bounded test controls:

```text
--dry-run --blueprint-id=316600 --max-blueprints=25 --max-products=250
```

Dry-run fetches and shapes rows but does not write Oracle. Keep all production
and probe runs bounded with explicit blueprint/product limits until counts and
duration are reviewed. The normal peer-host run is
`scripts/run-cardtrader-daily-market-refresh.sh`, which executes:

1. `scripts/refresh-cardtrader-market-listings.js` for the full market listing
   snapshot/removed-history import.
2. `scripts/refresh-cardtrader-blueprint-listing-cache.js` for the compact
   homepage/catalog cheapest-price projection only.

The import step calls `public.refresh_cardtrader_market_listing_snapshots(...)`
on peer4, which:

- upserts current rows into `public.cardtrader_market_listing_snapshots`;
- archives rows missing from the fresh export into
  `public.cardtrader_market_listing_removed_history`;
- dates removed/sold rows to the previous day by default (`current_date - 1`)
  because the sale/removal happened during the preceding ingestion window;
- avoids duplicate removed rows with the unique key
  `(provider, external_listing_id, removed_day)`;
- projects current and removed facts into
  `public.marketplace_price_observations` as `cardtrader_snapshot` and
  `cardtrader_removed_sale`;
- refreshes the graph/price observation projections, blueprint price summaries,
  CardTrader daily analytics, and homepage ranking rollups used by the card page
  graph and marketplace home modules.

The projection step writes `cheapest_homepage_cache_blueprint`, the
one-row-per-blueprint marketplace tile/card price source derived from the daily
backend listings cache/import. It stores eligible Zero + 1-Day Ready listing
counts and may include the cheapest EUR price converted to PKN plus the 200 PKN
reserve markup when safely available. It does not persist all CardTrader rows,
removed-history rows, or daily analytics. If production still writes
`public.cardtrader_blueprint_listing_cache`, that is the legacy physical table
name until a migration renames it.

The normal peer-host wrapper is intended to cover every known Pokémon CardTrader
blueprint in `public.marketplace_search_candidates`, not only the highest-ranked
sample. The script defaults are therefore broad (`100000` blueprints and
`1000000` products) and the apply path uses `--refresh-batch-blueprints=700` so
each batch archives only the blueprints it just fetched. Keep one-off diagnostics
bounded with explicit lower `--max-blueprints`, `--max-products`, or
`--blueprint-id` values, but do not install a production cron with the old sample
limits such as `--max-blueprints=250 --max-products=10000`.

Card page live listing API:

```text
GET /api/cardtrader-live-listings?blueprintId=316600
GET /api/cardtrader-live-listings?cardId=248856
```

This is the card detail page path when the UI needs to answer "which CardTrader
listings currently have this card?" It calls CardTrader live with the trusted
server global token (`CARDTRADER_AUTH_TOKEN`, falling back to
`CARDTRADER_API_TOKEN`) and does not write Oracle, Firebase, or any other DB.
When served by a Vercel compatibility function, configure one of those token env
vars in Vercel production; local or peer4-only env files are not enough for the
deployed route.
The route uses CardTrader `GET /api/v2/marketplace/products?blueprint_id=:id`,
which returns the cheapest current products grouped by CardTrader blueprint ID.

`blueprintId` is interpreted as a CardTrader blueprint ID. `cardId` is a Pokoin
card ID; numeric Pokoin IDs are resolved through Oracle card data when available,
and fall back to the same numeric value as the CardTrader blueprint ID because
Pokoin card identities are currently projected from CardTrader blueprints. The
CardTrader response is never persisted. The route keeps only a short in-process
cache and sends short HTTP cache headers to avoid repeated live calls on rapid
page reloads. The in-process cache is a per-Node-process `Map` with a 45-second
TTL, at most 100 entries, and keys shaped as
`cardtrader:<resolvedBlueprintId>:<language-or-empty>:<limit-or-all>`. Expired
entries are pruned on reads/writes; if the map is still over 100 entries, the
oldest insertion-order keys are removed. There is no distributed cache, DB write,
webhook invalidation, or admin invalidation endpoint; a process restart or
`clearLiveListingsCache()` in tests clears it. The response also sets
`Cache-Control: public, max-age=30, s-maxage=60`, so browser/CDN/proxy caching is
separate from the in-memory cache. Without `limit`, it returns every eligible row
CardTrader returns for the blueprint. Clients may pass `limit` to request fewer
rows; explicit limits are clamped to `1..1000` and only cap the response after
CardTrader has been fetched.

Responses contain safe current listing metadata: CardTrader product/listing id,
CardTrader blueprint id, product name/expansion, price/currency, buyer/seller
price fields when present, quantity, condition, language, description, inferred
`shippingMode`/`shippingLabel`, sanitized properties/raw metadata, public seller
fields, graded/vacation/bundle flags, and source/cache metadata. CardTrader does
not expose a direct shipping-type field in `marketplace/products`; the live route
infers `shippingMode` with these rules:

1. `one_day_ready`: only explicit seller/listing text matching `1-Day Ready` or
   `One Day Ready`.
2. `zero`: `can_sell_via_hub` or `can_sell_sealed_with_ct_zero`, when the listing
   is not one-day-ready.
3. `normal`: all other listings.

`max_sellable_in24h_quantity` alone must not classify a listing as
`one_day_ready`. Professional seller status alone must not classify a listing as
`zero`. For blueprint `248856`, known live examples are EeveeRaff and Mikebarocco
as `one_day_ready`, Lolimpodelnerd, Laconteacag, and Card Universe as `zero`, and
Tcg-mapro54_cardsita as `normal`. Do not expose global CardTrader tokens, seller
tokens, webhook shared secrets, encrypted secret envelopes, raw request headers,
or sensitive raw metadata keys.

Historical/daily snapshot read API:

```text
GET /api/cardtrader-blueprint-listings?blueprintId=316600
GET /api/cardtrader-blueprint-listings?cardId=274416
```

This is the Oracle/peer4-hosted historical/daily snapshot read path by
blueprint/card ID. `blueprintId` matches CardTrader blueprint columns; `cardId`
matches `pokoin_card_id` and numeric card IDs also check the blueprint columns
for compatibility with card pages that use the blueprint as the card identity.
Keep the contract as a snapshot read by blueprint/card ID.

The endpoint reads `public.cardtrader_market_listing_snapshots` with `limit`,
`page`, and `cursor` guardrails. It must not call CardTrader live; the live
lookup route above owns on-demand CardTrader calls. The daily Oracle ingestion
job above is responsible for calling CardTrader `GET /marketplace/products`,
upserting current snapshots, archiving missing listings in
`public.cardtrader_market_listing_removed_history`, and refreshing derived
price/analytics projections plus `cheapest_homepage_cache_blueprint`.
Marketplace home/catalog tile payloads read that projection for the cheapest
eligible Zero + 1-Day Ready price and must not call CardTrader live while
rendering tiles. If production still reads
`public.cardtrader_blueprint_listing_cache`, that is the legacy physical table
name for this projection until a migration renames it. Card detail seller
listings keep using the live parser so row-level seller, condition, comment,
flag, and price fields stay current and detailed.

Responses should contain only safe listing metadata: external listing id, card or
blueprint id, public seller fields, condition, language, quantity, price,
currency, sanitized properties/raw metadata, first/last seen timestamps, and
source import/update timestamps. Do not expose global CardTrader tokens, seller
tokens, webhook shared secrets, encrypted secret envelopes, raw ingestion headers,
or sensitive raw metadata keys.

Vercel may proxy this read route to the Oracle API service, or temporarily serve a
compatibility read function during rollout. Flutter card detail pages may call the
Pokoin API to show CardTrader current listings/metadata if needed, but Flutter
must never call CardTrader directly and must never receive secrets.

Required Oracle job env:

```text
CARDTRADER_AUTH_TOKEN # or CARDTRADER_API_TOKEN
MARKETPLACE_DATABASE_URL
PKN_CHECKOUT_USDT_PRICE # optional, defaults to 0.005 for EUR/USD-to-PKN projection
```

`MARKETPLACE_DATABASE_URL` must point at the peer4 writable primary unless the
primary runbook has promoted a different host. The expected peer4 env file on
this machine is `/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env`;
confirm it has `CARDTRADER_AUTH_TOKEN` or `CARDTRADER_API_TOKEN` before enabling
the cron. This peer4 token is required even when Vercel production also has a
CardTrader token for compatibility/live routes. Do not log global or seller
CardTrader tokens. Dry-run/manual diagnostic output should return counts and
small redacted samples only.

Example peer4 dry-run:

```bash
cd /Users/giuseppe/cardvault/pokemon_card_vault
node scripts/refresh-cardtrader-market-listings.js \
  --env-file=/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env \
  --dry-run \
  --blueprint-id=316600 \
  --max-blueprints=25 \
  --max-products=250
```

Example peer4 crontab entry after the dry-run is reviewed:

```cron
20 3 * * * cd /Users/giuseppe/cardvault/pokemon_card_vault && bash scripts/run-cardtrader-daily-market-refresh.sh >> /var/log/pokoin-cardtrader-market-refresh.log 2>&1
```

Verification queries after a dry-run or scheduled apply:

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

select count(*) as daily_analytics_rows
from public.cardtrader_blueprint_daily_analytics
where observed_day >= current_date - 7;

select count(*) as hot_blueprint_rows
from public.marketplace_hot_blueprints;
```

Seller `GET /products/export` sync/import dry-runs are still part of the
connected-seller workflow above. Keep them separate from global marketplace
analytics; seller exports describe one seller's own CardTrader inventory, while
`/marketplace/products` describes public CardTrader market listings for
blueprints.

## Future Live Sync Phases

Live two-way inventory updates are intentionally not enabled in the first slice.
Add these phases before any destructive CardTrader or Pokoin inventory writes:

1. Add durable `cardtrader_sync_events` or equivalent idempotency records keyed by
   CardTrader order/product/job IDs and Pokoin listing IDs.
2. Import CardTrader product export into a staging table/document collection with
   deterministic mapping to Pokoin blueprints and seller listings.
3. Add an explicit seller review/confirm step for proposed listing creations,
   price changes, and quantity changes.
4. Process sale decrements only once:
   - Standard CardTrader orders decrement at `state=paid`.
   - CardTrader Zero orders decrement at `state=hub_pending`.
   - Do not double decrement CT0 `paid` merged orders.
5. Verify CardTrader webhooks using the encrypted `shared_secret`; only decrypt
   it inside trusted server handlers.
6. Add replay-safe workers for bulk jobs and inventory reconciliation with
   retries, audit logs, and tests around duplicate delivery.
7. Only after the above, enable live calls to `POST /products`, `PUT /products/:id`,
   `DELETE /products/:id`, `POST /products/:id/increment`, or bulk job endpoints.

## Verification

Before deploy, run:

```bash
node --check api/_cardtrader_crypto.js api/_cardtrader_client.js api/_cardtrader_daily_listings_refresh.js api/_cardtrader_integration.js api/cardtrader-connect.js api/cardtrader-status.js api/cardtrader-disconnect.js api/cardtrader-clean-listings.js api/cardtrader-import-dry-run.js api/cardtrader-daily-listings-refresh.js scripts/refresh-cardtrader-market-listings.js api/marketplace-card-sales.js
node --test api/cardtrader-connect.test.js api/cardtrader-daily-listings-refresh.test.js api/marketplace-card-sales.test.js
dart format lib/services/cardtrader_integration_service.dart lib/providers/cardtrader_integration_provider.dart lib/screens/cardtrader_connect_screen.dart lib/main.dart lib/screens/home_screen.dart lib/models/card_listing.dart lib/screens/card_detail_screen.dart
flutter analyze
git diff --check -- api server scripts lib docs workflows oracle-postgres/schema deploy-pokoin-web.sh vercel.json
```

Do not deploy from this workflow unless explicitly requested.
