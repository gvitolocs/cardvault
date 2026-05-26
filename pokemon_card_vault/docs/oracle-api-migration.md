# Oracle API Migration And Route Reference

This document tracks the first version of moving Pokoin backend API routes from
many Vercel serverless functions into one long-running Node service suitable for
Oracle/peer3. It is generated from `server/api-route-manifest.js` so the route
list stays tied to the standalone server configuration.

## Architecture

- Static Flutter web remains deployed by Vercel.
- Existing handlers in `api/*.js` remain the business-logic source of truth.
- `server/oracle-api-server.js` adapts Node HTTP requests to the current
  Vercel-style `handler(req, res)` API, including `req.query`, JSON bodies,
  Vercel-like response helpers, and legacy `.js` route compatibility.
- `/healthz` and `/api/healthz` expose service health. `/api/__routes`
  exposes a compact route index.
- `/api/stripe-webhook` is treated as a raw-body route and is not JSON parsed
  before the existing Stripe signature code reads the request stream.

## peer3 Discovery

`web/bootstrap-peers.json` contains `oracle-peer-3` / `pokoin-vm3` at
`141.147.62.244` for the Pokoin peer network. Local SSH config also resolves
`peer3`, but no repository script previously deployed this API service there.
The new deployment script uses `ORACLE_API_SSH_TARGET` with a default of
`peer3`; it does not include or assume credentials.

## Running Locally

```bash
npm run api:server
```

Useful local variables:

```text
PORT=8080
ORACLE_API_HOST=0.0.0.0
ORACLE_API_JSON_LIMIT_BYTES=10485760
ORACLE_API_BASE_URL=https://api.example.com
```

The backend also needs the same service env vars already required by the Vercel
functions, such as Firebase Admin, Oracle/Postgres marketplace URLs, Supabase,
Stripe, R2, and Pokoin RPC keys. Keep values out of docs and logs.

## Production Cutover

`vercel.json` proxies `/api/*` to the Oracle service when
`deploy-pokoin-web.sh` runs with `ORACLE_API_BASE_URL`. Keep this rewrite
before all local `/api/*.js` rewrites:

```json
{
  "source": "/api/:path*",
  "destination": "$ORACLE_API_BASE_URL/api/:path*"
}
```

The production backend base URL is `https://api.pokoin.com`. Treat this API
origin as first-class production infrastructure. `deploy-pokoin-web.sh`
switches to the no-serverless workflow whenever `ORACLE_API_BASE_URL` is set
or `USE_ORACLE_API=1` is set. In that mode the web build must not copy
`api/*.js`, `server/*`, `package.json`, or `package-lock.json` into
`build/web`, so Vercel deploys a static Flutter frontend and proxies
`/api/*` to the Oracle API service. Avoid the checked-in Vercel serverless
fallback unless explicitly requested for an emergency rollback.

Do not run the production Vercel deploy until `https://api.pokoin.com` is
healthy. A broken API origin would make production `/api/*` routes fail.

## Production Deployment Commands

The Oracle/peer3 backend service should be exposed at `api.pokoin.com`.
For production keep the workflow simple: `pokoin.com` serves only the Vercel
Flutter frontend, and every `/api/*` request rewrites to `api.pokoin.com`.

Before switching production, verify the backend directly:

```bash
curl -fsS https://api.pokoin.com/marketplace >/dev/null
curl -fsS https://api.pokoin.com/healthz
curl -fsS https://api.pokoin.com/api/__routes
```

Deploy production with no bundled Vercel functions only after those origin
checks pass:

```bash
ORACLE_API_BASE_URL=https://api.pokoin.com \
POKOIN_WEB_DEPLOY_TARGET=production \
./deploy-pokoin-web.sh
```

After deployment, verify the production frontend and API rewrite:

```bash
curl -fsS https://pokoin.com/ >/dev/null
curl -fsS https://pokoin.com/marketplace >/dev/null
curl -fsS https://pokoin.com/api/healthz
curl -fsS https://pokoin.com/api/__routes
```

DNS target: `api.pokoin.com` should point at Oracle peer3 `141.147.62.244`
through the configured reverse proxy/TLS layer. `pokoin.com` should point at
Vercel for the frontend.

Backend landing page:

```text
https://api.pokoin.com/marketplace
```

Package only:

```bash
npm run peer3:bundle
```

Upload to peer3 without starting:

```bash
ORACLE_API_SSH_TARGET=peer3 npm run peer3:deploy -- --no-restart
```

Upload and restart with PM2 if available, otherwise `nohup`:

```bash
ORACLE_API_SSH_TARGET=peer3 \
ORACLE_API_REMOTE_DIR=/opt/pokoin/oracle-api \
ORACLE_API_PORT=8080 \
npm run peer3:deploy
```

If `api.pokoin.com` is reachable at DNS but HTTP/S times out, check peer3's
firewall and reverse proxy before deploying production:

```bash
sudo ss -ltnp | grep -E ':(80|443|8080)\\b'
sudo systemctl status nginx --no-pager || true
sudo systemctl status caddy --no-pager || true
curl -fsS http://127.0.0.1:8080/healthz
```

OCI peer3 ingress must allow public TCP `80` and `443` to the VM. The API
container should stay bound to `127.0.0.1:18080` behind Caddy; avoid exposing
the internal API port publicly unless it is an intentional temporary diagnostic.

The script deliberately does not copy `.env.local`; provide production
environment variables through the host supervisor or service env file.

## CardTrader Live And Snapshot Routes

The card detail page live route is:

```text
GET /api/cardtrader-live-listings?blueprintId=316600
GET /api/cardtrader-live-listings?cardId=248856
```

This route calls CardTrader `GET /api/v2/marketplace/products?blueprint_id=:id`
with the trusted server global token (`CARDTRADER_AUTH_TOKEN` or legacy
fallback `CARDTRADER_API_TOKEN`) and does not persist the returned listings.
`blueprintId` is a CardTrader blueprint ID; `cardId` is a Pokoin card ID that
can be resolved through Oracle card data, with numeric IDs falling back to the
same CardTrader blueprint value. Responses include safe public listing metadata
only and use short in-process/HTTP caching. Without a `limit` query param, the
route returns all rows CardTrader returns for the blueprint; explicit limits only
cap the client response. Live rows include inferred
`shippingMode`/`shippingLabel` metadata; CardTrader does not expose a direct
shipping-type field, so the route derives one-day-ready only from explicit
`1-Day Ready` seller/listing text, then derives CardTrader Zero from hub/Zero
flags such as `can_sell_via_hub` or
`can_sell_sealed_with_ct_zero`. Professional seller status alone is not a Zero
signal, and the inferred metadata is not persisted.

The Oracle/peer4-hosted historical/daily snapshot read route is:

```text
GET /api/cardtrader-blueprint-listings?blueprintId=316600
GET /api/cardtrader-blueprint-listings?cardId=274416
```

`blueprintId` matches CardTrader blueprint columns. `cardId` matches
`pokoin_card_id` and numeric values also check the blueprint columns for
compatibility with card pages that use blueprint IDs as card IDs. The route reads
current public listing metadata from
`public.cardtrader_market_listing_snapshots`; it must not call CardTrader live.
Daily ingestion on peer4 owns snapshot writes from `GET /marketplace/products`,
snapshot upserts, and removed-history writes to
`public.cardtrader_market_listing_removed_history`. The same peer4 ingestion
path refreshes `public.cardtrader_blueprint_listing_cache`, the one-row-per-
blueprint availability cache used by marketplace home/catalog tile payloads to
avoid false out-of-stock states. It may provide a cheapest effective PKN hint
when safely available, but card detail/version rows and seller listing detail
must not use this cache in place of the live CardTrader parser. Tile rendering
must read that Oracle cache internally rather than making CardTrader live calls.

Vercel should proxy these routes to the Oracle API service when `/api/*` is
routed to `api.pokoin.com`, or serve only temporary compatibility functions
during rollout. Flutter may use the live route on card pages to show CardTrader
current listings/metadata, but responses must contain safe public fields only and
never return tokens, shared secrets, encrypted secret envelopes, raw ingestion
headers, or unbounded CardTrader source payloads.

The generated manifest below lists both routes when the standalone handler and
Vercel compatibility rewrite are available.

## API Routes

### /api/auth-login

- File: `api/auth-login.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Validate the current Firebase bearer token and return safe auth metadata.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: No required JSON body fields.
- Notable env vars: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`
- External dependencies: Firebase Admin

### /api/cache-google-profile-picture

- File: `api/cache-google-profile-picture.js`
- Methods: `POST`
- Purpose: Download the authenticated user Google avatar, optimize it, and store it in R2.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: No required fields; uses the authenticated Firebase profile picture URL.
- Notable env vars: `FIREBASE_*`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PROFILE_PICTURES_BUCKET`, `R2_PROFILE_PICTURES_PUBLIC_URL`
- External dependencies: Firebase Admin, Cloudflare R2, sharp

### /api/cardmarket-redirect

- File: `api/cardmarket-redirect.js`
- Methods: `GET`
- Purpose: Resolve a marketplace blueprint to a Cardmarket product/search URL and redirect, or return JSON when requested.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `id` required blueprint ID, `locale` optional two-letter locale, `format=json` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/cardmarket-scrape-observation

- File: `api/cardmarket-scrape-observation.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Record Cardmarket scrape/association observations used by marketplace import review tooling.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Cardmarket observation payload including blueprint/product identifiers and scrape metadata.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/cardtrader-blueprint-listings

- File: `api/cardtrader-blueprint-listings.js`
- Methods: `GET`, `OPTIONS`
- Purpose: Return historical/daily CardTrader marketplace listing snapshots for one blueprint/card ID from Oracle.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `blueprintId` required for CardTrader blueprint IDs; `cardId` accepted for mapped Pokoin card IDs; `limit`, `page`, and `cursor` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/cardtrader-live-listings

- File: `api/cardtrader-live-listings.js`
- Methods: `GET`, `OPTIONS`
- Purpose: Return live on-demand CardTrader marketplace listings for one blueprint/card ID without persisting results.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `blueprintId` for a CardTrader blueprint ID or `cardId` for a Pokoin card ID such as `248856`; `language`/`lang` and `limit` optional. Without `limit`, returns all rows from CardTrader for the blueprint; explicit limits cap the client response only.
- Notable env vars: `CARDTRADER_AUTH_TOKEN`, `CARDTRADER_API_TOKEN`, `MARKETPLACE_DATABASE_URL`
- External dependencies: CardTrader API, Oracle/Postgres marketplace DB for optional cardId mapping

### /api/cardtrader-clean-listings

- File: `api/cardtrader-clean-listings.js`
- Methods: `POST`
- Purpose: Deactivate CardTrader-linked listings owned by the authenticated seller.
- Auth: Required Firebase bearer token for the seller.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: No required fields.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/cardtrader-connect

- File: `api/cardtrader-connect.js`
- Methods: `POST`, `DELETE`
- Purpose: Connect, replace, or disconnect an authenticated seller CardTrader token.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `token` required for POST. DELETE has no body.
- Notable env vars: `CARDTRADER_TOKEN_ENCRYPTION_KEY`, `FIREBASE_*`
- External dependencies: Firebase Admin, CardTrader API

### /api/cardtrader-daily-listings-refresh

- File: `api/cardtrader-daily-listings-refresh.js`
- Methods: `GET`, `POST`
- Purpose: Manual/admin diagnostic trigger for global CardTrader marketplace listing snapshots; scheduled ingestion is owned by the Oracle/peer4 host script.
- Auth: Required CARDTRADER_DAILY_LISTINGS_SECRET, CARDTRADER_DAILY_REFRESH_SECRET, or CRON_SECRET bearer/header secret.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `dryRun`, `maxBlueprints`, `maxProducts`, `archiveMissing`, `removedDay`, `blueprintId`, `blueprintIds`, `expansionId`, and `language` are optional bounded controls.
- body: Same controls as query parameters for POST.
- Notable env vars: `CARDTRADER_AUTH_TOKEN`, `CARDTRADER_API_TOKEN`, `CARDTRADER_DAILY_LISTINGS_SECRET`, `CRON_SECRET`, `MARKETPLACE_DATABASE_URL`, `PKN_CHECKOUT_USDT_PRICE`
- External dependencies: CardTrader API, Oracle/Postgres marketplace DB

### /api/cardtrader-disconnect

- File: `api/cardtrader-disconnect.js`
- Methods: `POST`
- Purpose: Disconnect the authenticated seller CardTrader integration.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: No required fields.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/cardtrader-import-dry-run

- File: `api/cardtrader-import-dry-run.js`
- Methods: `POST`
- Purpose: Read the authenticated seller CardTrader export and return a redacted import summary without writing inventory.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Optional dry-run controls; no writes are performed.
- Notable env vars: `CARDTRADER_TOKEN_ENCRYPTION_KEY`, `FIREBASE_*`
- External dependencies: Firebase Admin, CardTrader API

### /api/cardtrader-redirect

- File: `api/cardtrader-redirect.js`
- Methods: `GET`
- Purpose: Redirect a CardTrader blueprint ID to CardTrader.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `id` required numeric CardTrader blueprint ID.
- Notable env vars: None documented.
- External dependencies: CardTrader website

### /api/cardtrader-status

- File: `api/cardtrader-status.js`
- Methods: `GET`
- Purpose: Return safe CardTrader integration status for the authenticated seller.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: No required query parameters.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/create-pkn-checkout-session

- File: `api/create-pkn-checkout-session.js`
- Methods: `POST`
- Purpose: Create or reconcile a Stripe Checkout session for buying PKN account balance.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `pknAmount`, `fiatCents`, and `lookupKey` for new checkout; `checkoutSessionId` for reconciliation.
- Notable env vars: `STRIPE_SECRET_KEY`, `STRIPE_API_VERSION`, `PUBLIC_SITE_URL`, `PKN_CHECKOUT_CURRENCY`, `PKN_CHECKOUT_USDT_PRICE`, `FIREBASE_*`
- External dependencies: Stripe, Firebase Admin

### /api/crypto-pkn-purchase/:action

- File: `api/crypto-pkn-purchase.js`
- Methods: `GET`, `POST`
- Purpose: Quote, request, and check crypto-to-PKN purchase flows.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- path: `action` is `quote`, `request`, or `status`.
- body: `asset` and `amountIn` for quote; `quoteId` and `depositTxHash` for request.
- query: `requestId` optional for status.
- Notable env vars: `FIREBASE_*`, `POKOIN_RPC_URL`, `POKOIN_BANK_ADDRESS`, `POKOIN_BANK_PRIVATE_KEY`
- External dependencies: Firebase Admin, Pokoin RPC, configured crypto RPCs

### /api/crypto-pkn-sale/:action

- File: `api/crypto-pkn-sale.js`
- Methods: `GET`, `POST`
- Purpose: Quote, request, and check PKN-to-crypto sale flows.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- path: `action` is `quote`, `request`, or `status`.
- body: `asset` and `amountIn` for quote; `quoteId`, `depositTxHash`, and `payoutAddress` for request.
- query: `requestId` optional for status.
- Notable env vars: `CRYPTO_PKN_SELL_ENABLED`, `CRYPTO_PKN_AUTO_PAYOUT_ENABLED`, `FIREBASE_*`, `POKOIN_RPC_URL`, `POKOIN_BANK_ADDRESS`, `POKOIN_BANK_PRIVATE_KEY`
- External dependencies: Firebase Admin, Pokoin RPC, configured crypto payout services

### /api/deck-card-version-lookup

- File: `api/deck-card-version-lookup.js`
- Methods: `GET`, `POST`, `OPTIONS`
- Purpose: Return ranked marketplace card versions for structured decklist card fields.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `name`, `setCode`, `collectorNumber`, optional Limitless expansion fields, `language`, and `limit` are supported.
- body: Same fields as query parameters for POST.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/extension-card-search

- File: `api/extension-card-search.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Search marketplace cards from browser-extension scraped card fields.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `query` or structured fields such as `name`, `collectorNumber`, `expansion`, `rarity`, `variation`, `language`, and `limit`.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_*_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/earn-pkn

- File: `api/earn-pkn.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Receive Earn PKN sharding inquiries and email the completed form to Pokoin contact.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `email`, `numberOfCards`, and `valueOfCards` required; optional `cardList`, `language`, and `conditions`.
- Notable env vars: `RESEND_API_KEY`, `EARN_PKN_EMAIL_TO`, `EARN_PKN_EMAIL_FROM`
- External dependencies: email provider

### /api/flutter-debug-logs

- File: `api/flutter-debug-logs.js`
- Methods: `GET`, `POST`
- Purpose: Record and read protected Flutter client debug logs.
- Auth: Required debug token or authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET filters include `limit`, `sessionId`, `userId`, `path`, `category`, and `eventName`.
- body: POST requires `sessionId` and `eventName`, with optional route/url/user/payload fields.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FLUTTER_DEBUG_LOG_TOKEN`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin for debug auth

### /api/forum

- File: `api/forum.js`
- Methods: `GET`
- Purpose: Read forum categories, topic lists, or a single topic with posts.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `categoryId` optional for topic lists, `topicId` optional for a single topic.
- Notable env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- External dependencies: Supabase REST

### /api/forum-create-post

- File: `api/forum-create-post.js`
- Methods: `POST`
- Purpose: Create an authenticated forum reply.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `topicId` and post content fields.
- Notable env vars: `FIREBASE_*`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- External dependencies: Firebase Admin, Supabase REST

### /api/forum-create-topic

- File: `api/forum-create-topic.js`
- Methods: `POST`
- Purpose: Create an authenticated forum topic.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Topic title/content/category fields.
- Notable env vars: `FIREBASE_*`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- External dependencies: Firebase Admin, Supabase REST

### /api/forum-upload-media

- File: `api/forum-upload-media.js`
- Methods: `POST`
- Purpose: Optimize forum image media and store it in R2.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `imageBase64` and either `topicId` or `postId`.
- Notable env vars: `FIREBASE_*`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_FORUM_MEDIA_BUCKET`, `R2_FORUM_MEDIA_PUBLIC_URL`
- External dependencies: Firebase Admin, Supabase REST, Cloudflare R2, sharp

### /api/limitless-expansion-blueprints

- File: `api/limitless-expansion-blueprints.js`
- Methods: `GET`
- Purpose: Return Limitless expansion-to-Pokoin blueprint mapping rows.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `expansionKey`, `setCode`, `name`, `includeBlueprints=1`, and `limit` are supported.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-artist-cards

- File: `api/marketplace-artist-cards.js`
- Methods: `GET`
- Purpose: Return artist profile data and marketplace cards grouped by illustrator/artist attribution.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `artistSlug` or `artist`; `limit` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-artist-suggestions

- File: `api/marketplace-artist-suggestions.js`
- Methods: `GET`
- Purpose: Return marketplace artist suggestion rows for artist pages and admin review.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: Search/filter query parameters including artist text and limit.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-autocomplete

- File: `api/marketplace-autocomplete.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Return ranked marketplace autocomplete/search suggestions with optional debug metadata.
- Auth: Public for normal search; debug and personalization use optional Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `search_term`/`query`, `result_limit`, `pool_limit`, `search_language`, optional previous context and debug fields.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_NAME_SEARCH_DATABASE_URL`, `MARKETPLACE_PEER1_DATABASE_URL`, `MARKETPLACE_PEER2_DATABASE_URL`, `MARKETPLACE_PEER3_DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_NAME_INDEX_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB, optional Supabase name index, Firebase Admin for optional auth

### /api/marketplace-blueprint-price

- File: `api/marketplace-blueprint-price.js`
- Methods: `GET`, `OPTIONS`
- Purpose: Return the public PKN floor price for a marketplace blueprint/card ID.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `blueprintId` required; `cardId` accepted as an alias.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `PKN_CHECKOUT_USDT_PRICE`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-card-cheapest-price

- File: `api/marketplace-card-cheapest-price.js`
- Methods: `GET`, `OPTIONS`
- Purpose: Return the homepage-backed cheapest marketplace price for a card, including CardTrader cache availability.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId`, `cardIds`, `canonicalPath`, or structured `name`/`setName`/`collectorNumber`; `language` and bounded `limit` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `PKN_CHECKOUT_USDT_PRICE`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-card-seo

- File: `api/marketplace-card-seo.js`
- Methods: `GET`
- Purpose: Return server-rendered HTML metadata for marketplace card social previews.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId`, `cardSlug`, `language`, or `cardPath` depending on the rewrite source.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-card-sales

- File: `api/marketplace-card-sales.js`
- Methods: `GET`
- Purpose: Return recent paid sale history for a marketplace card from Firestore orders.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId` required, `limit` optional.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/marketplace-card-shortlink

- File: `api/marketplace-card-shortlink.js`
- Methods: `GET`, `HEAD`
- Purpose: Redirect numeric root short links to canonical marketplace card URLs.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId` required via rewrite or query string.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-card-url

- File: `api/marketplace-card-url.js`
- Methods: `GET`, `HEAD`
- Purpose: Return the stored canonical marketplace card URL for a card id or legacy root path.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId` or `path` required; `language` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-card-versions

- File: `api/marketplace-card-versions.js`
- Methods: `GET`
- Purpose: Return card detail/version rows for marketplace card pages.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId`, `sameAsCardId`, `cardSlug`, `expansionName`, `query`, `limit`, `productType`, and `language` are supported.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-cardmarket-guess-review

- File: `api/marketplace-cardmarket-guess-review.js`
- Methods: `GET`
- Purpose: Return protected Cardmarket guess review data for search/debug operators.
- Auth: Required authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: Review filters and pagination query parameters.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-cards

- File: `api/marketplace-cards.js`
- Methods: `GET`
- Purpose: Return searchable marketplace card and product rows.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `query`, `limit`, `language`, `productType`, and `productSearchOnly` are supported.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-debug-artists

- File: `api/marketplace-debug-artists.js`
- Methods: `GET`, `POST`
- Purpose: Inspect and update marketplace artist enrichment/debug classification data.
- Auth: Required authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET filters for artist debug views.
- body: `action` plus action-specific artist/classification payload for POST.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-debug-cardtrader-blueprints

- File: `api/marketplace-debug-cardtrader-blueprints.js`
- Methods: `GET`, `POST`
- Purpose: Inspect and enqueue protected CardTrader blueprint debug/import work.
- Auth: Required authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET filters/status fields.
- body: POST queue/review payload fields.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-debug-events

- File: `api/marketplace-debug-events.js`
- Methods: `GET`
- Purpose: Return marketplace event analytics debug data.
- Auth: Required authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: Event/card/search filters and limits.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-debug-refinement

- File: `api/marketplace-debug-refinement.js`
- Methods: `GET`, `POST`
- Purpose: Inspect and update marketplace search refinement/debug data.
- Auth: Required authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET refinement filters.
- body: POST action-specific refinement payload.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-event

- File: `api/marketplace-event.js`
- Methods: `POST`
- Purpose: Record public marketplace interaction/search events and refresh hot-card aggregates opportunistically.
- Auth: Public; optional Firebase bearer token attaches user UID when valid.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `cardId`, `eventType`, optional `source` and bounded metadata.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, optional Firebase Admin

### /api/marketplace-expansion-symbols

- File: `api/marketplace-expansion-symbols.js`
- Methods: `GET`, `POST`
- Purpose: Read or update marketplace expansion symbol metadata.
- Auth: Required authorized debug/admin Firebase bearer token for both GET and POST.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET filters for expansions.
- body: Expansion symbol update fields for POST.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-expansions

- File: `api/marketplace-expansions.js`
- Methods: `GET`
- Purpose: Return marketplace expansion list or detail snapshots.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: Expansion slug/id/detail filters and optional limit.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-home

- File: `api/marketplace-home.js`
- Methods: `GET`
- Purpose: Return marketplace home snapshot and carousel sections.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: No required query parameters.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-competitive

- File: `api/marketplace-competitive.js`
- Methods: `GET`
- Purpose: Return Limitless-backed competitive deck metagame, deck detail, tournament, standings, and pairings data for the marketplace competitive page.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `game`, `format`, `year`, `limit`, and `includeGames=1` for the dashboard; `deckId` for public Limitless deck detail; `tournamentId` for tournament standings/pairings detail.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-hot-blueprints

- File: `api/marketplace-hot-blueprints.js`
- Methods: `GET`
- Purpose: Return hot marketplace blueprint rows and rolling interaction counts.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `includeCards` and `limit` optional.
- Notable env vars: `MARKETPLACE_DATABASE_URL`
- External dependencies: Oracle/Postgres marketplace DB

### /api/marketplace-listings

- File: `api/marketplace-listings.js`
- Methods: `GET`, `POST`, `PATCH`
- Purpose: Read public active listings and create/update/decrement authenticated seller listings.
- Auth: Public for active listing reads; writes and seller-owned reads require Firebase bearer token. Reserve listings require reserve role.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `cardId`, `sellerUid`, `sellerUsername`, `id`, `action`, and `limit` supported.
- body: Create/update listing fields such as `cardId`, seller display fields, condition, language, `pricePkn`, quantity, and source flags.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin

### /api/marketplace-orders

- File: `api/marketplace-orders.js`
- Methods: `POST`
- Purpose: Create paid marketplace orders, decrement listings, credit sellers, and send seller notifications.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `action=checkout` default, `action=notify-sellers` for notification retry/admin flows.
- body: `items`, `subtotalPkn`, and `totalPkn` for checkout; notification payload for notify-sellers.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`, `RESEND_API_KEY`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin, email provider

### /api/marketplace-search-candidates

- File: `api/marketplace-search-candidates.js`
- Methods: `POST`
- Purpose: Return split/search candidate rows for marketplace search diagnostics and clients.
- Auth: Public for normal search; debug output requires authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `search_term`/`searchTerm`, `result_limit`, `result_offset`, `search_language`, optional previous context/debug fields.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_*_DATABASE_URL`, `MARKETPLACE_ADMIN_EMAILS`, `MARKETPLACE_DEBUG_EMAILS`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin for debug auth

### /api/pokoin-assistant

- File: `api/pokoin-assistant.js`
- Methods: `POST`
- Purpose: Answer Pokontact assistant chat requests with marketplace grounding and optional service handoff.
- Auth: Public; optional Firebase bearer token attaches verified user context.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `message` required, optional `messages`, `page`, `pageContext`, and `username`.
- Notable env vars: `POKOIN_ASSISTANT_EMAIL`, `POKOIN_ASSISTANT_FROM`, `POKONTACT_SERVICE_URL`, `POKONTACT_SERVICE_TOKEN`, `POKONTACT_SERVICE_TIMEOUT_MS`, `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`, `RESEND_API_KEY`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin optional, email provider, optional Pokontact service

### /api/user-current-page

- File: `api/user-current-page.js`
- Methods: `GET`, `POST`
- Purpose: Store or read the current internal Pokoin page for an assistant browser session.
- Auth: Public anonymous session ID; optional Firebase bearer token scopes reads/writes to the verified user.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: GET accepts `sessionId` or `session_id`.
- body: POST requires `sessionId` and a safe internal `path` or Pokoin URL; optional `source`.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Oracle/Postgres marketplace DB, Firebase Admin optional

### /api/social-autopost

- File: `api/social-autopost.js`
- Methods: `POST`
- Purpose: Post supplied Pokoin social copy or card payloads to configured Telegram and X channels, optionally using the dedicated peer2 social copy agent.
- Auth: Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `targets`, `message`, optional card fields, `dryRun`, `sendPhoto`, `silent`, and `useAgent`.
- Notable env vars: `SOCIAL_AUTOPOST_SECRET`, `CRON_SECRET`, `SOCIAL_AGENT_ENDPOINT`, `SOCIAL_AGENT_TOKEN`, `SOCIAL_AGENT_TIMEOUT_MS`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHANNEL_ID`, `X_ACCESS_TOKEN`, `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Telegram Bot API, X API v2, dedicated peer2 social agent optional, Oracle/Postgres marketplace DB optional, Firebase Admin optional

### /api/social-autopost/hot-card

- File: `api/social-autopost-hot-card.js`
- Methods: `GET`, `POST`
- Purpose: Select a hot Pokoin marketplace card and post it to configured social channels, optionally using the dedicated peer2 social copy agent.
- Auth: Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `targets`, `window`, `limit`, `dryRun`, `sendPhoto`, `silent`, and `useAgent` for GET.
- body: Same fields as query for POST; optional `message`, `hook`, and `hashtags` override generated copy.
- Notable env vars: `SOCIAL_AUTOPOST_SECRET`, `CRON_SECRET`, `SOCIAL_AGENT_ENDPOINT`, `SOCIAL_AGENT_TOKEN`, `SOCIAL_AGENT_TIMEOUT_MS`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHANNEL_ID`, `X_ACCESS_TOKEN`, `MARKETPLACE_DATABASE_URL`, `FIREBASE_*`
- External dependencies: Telegram Bot API, X API v2, dedicated peer2 social agent optional, Oracle/Postgres marketplace DB, Firebase Admin optional

### /api/social-post-agent

- File: `api/social-post-agent.js`
- Methods: `POST`
- Purpose: Generate Telegram and X copy through the dedicated peer2 social agent without posting to providers.
- Auth: Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `targets`, card/message fields, and optional `prompt`; returns generated copy and deterministic fallback metadata.
- Notable env vars: `SOCIAL_AUTOPOST_SECRET`, `CRON_SECRET`, `SOCIAL_AGENT_ENDPOINT`, `SOCIAL_AGENT_TOKEN`, `SOCIAL_AGENT_TIMEOUT_MS`, `FIREBASE_*`
- External dependencies: dedicated peer2 social agent optional, Firebase Admin optional

### /api/register-email

- File: `api/register-email.js`
- Methods: `POST`
- Purpose: Start email/password signup by storing pending signup data and sending verification mail.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `email`, password fields, and optional requested username/profile fields.
- Notable env vars: `FIREBASE_*`, `RESEND_API_KEY`, `PUBLIC_SITE_URL`, `PENDING_SIGNUP_SECRET`
- External dependencies: Firebase Admin, email provider

### /api/remove-profile-picture

- File: `api/remove-profile-picture.js`
- Methods: `POST`
- Purpose: Remove the authenticated user custom profile picture and delete old R2 object when present.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: No required fields.
- Notable env vars: `FIREBASE_*`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PROFILE_PICTURES_BUCKET`
- External dependencies: Firebase Admin, Cloudflare R2

### /api/request-pkn-withdraw

- File: `api/request-pkn-withdraw.js`
- Methods: `POST`
- Purpose: Withdraw PKN from site balance to a linked native PKN address.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Withdrawal amount/address or linked-wallet withdrawal fields used by the wallet UI.
- Notable env vars: `FIREBASE_*`, `POKOIN_RPC_URL`, `POKOIN_BANK_ADDRESS`, `POKOIN_BANK_PRIVATE_KEY`
- External dependencies: Firebase Admin, Pokoin RPC

### /api/search-recipient-emails

- File: `api/search-recipient-emails.js`
- Methods: `GET`, `POST`
- Purpose: Search usernames for transfers, ensure a username, or update the authenticated user username.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `q` for GET username search.
- body: Optional `username` for POST update; empty POST ensures a unique username.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/searchbar-cancel

- File: `api/searchbar-cancel.js`
- Methods: `GET`, `POST`
- Purpose: Mark a searchbar session as cancelled for in-process search cancellation checks.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `search_session_id`/`sessionId` supported.
- body: `search_session_id`/`sessionId` supported.
- Notable env vars: None documented.
- External dependencies: In-process search session memory

### /api/searchbar-cards

- File: `api/searchbar-cards.js`
- Methods: `GET`, `POST`
- Purpose: Stable wrapper around marketplace autocomplete ranking for searchbar experiments and clients.
- Auth: Public; debug/personalization may use optional Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `query`, `search_language`, `limit`, and `pool_limit` supported for GET.
- body: `query`, `search_language`, `limit`, `pool_limit`, previous context, debug, and mode fields for POST.
- Notable env vars: `MARKETPLACE_DATABASE_URL`, `MARKETPLACE_*_DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- External dependencies: Oracle/Postgres marketplace DB, optional Supabase name index

### /api/searchbar-token-predict

- File: `api/searchbar-token-predict.js`
- Methods: `GET`, `POST`, `OPTIONS`
- Purpose: Return lightweight card-name token predictions for active typed fragments.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- query: `query`, `search_language`, and `limit` for GET.
- body: `query`, `search_language`, `limit`, and optional previous prediction context for POST.
- Notable env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_NAME_INDEX_DATABASE_URL`, `MARKETPLACE_DATABASE_URL`
- External dependencies: Supabase REST/Postgres token table, Oracle/Postgres fallback

### /api/signup-notification

- File: `api/signup-notification.js`
- Methods: `POST`
- Purpose: Send signup notification email for the authenticated user once.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Optional signup/profile metadata.
- Notable env vars: `FIREBASE_*`, `RESEND_API_KEY`
- External dependencies: Firebase Admin, email provider

### /api/stripe-webhook

- File: `api/stripe-webhook.js`
- Methods: `POST`
- Purpose: Handle Stripe Checkout webhooks and credit completed PKN purchases.
- Auth: Stripe webhook signature using raw request body.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Raw Stripe webhook payload. Do not pre-parse JSON before signature verification.
- Notable env vars: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_API_VERSION`, `FIREBASE_*`
- External dependencies: Stripe, Firebase Admin
- Raw body: required. The standalone server does not pre-parse this route so Stripe signature verification receives the original bytes.

### /api/top-up-account-balance

- File: `api/top-up-account-balance.js`
- Methods: `POST`
- Purpose: Verify a native PKN funding transaction and credit authenticated site balance.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `amountPkn`, `fundingTxHash`, and optional `reconcileRecent`.
- Notable env vars: `FIREBASE_*`, `POKOIN_RPC_URL`, `POKOIN_BANK_ADDRESS`
- External dependencies: Firebase Admin, Pokoin RPC

### /api/trainingai-card-classify

- File: `api/trainingai-card-classify.js`
- Methods: `POST`, `OPTIONS`
- Purpose: Proxy card image classification requests to the Pokoin TrainingAI Oracle classifier or Hugging Face Space fallback.
- Auth: Public by default; protect upstream classifier with TRAININGAI_HF_TOKEN when private.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `imageBase64` JSON or multipart image upload required; `topK`/`top_k` optional from 1 to 10.
- Notable env vars: `TRAININGAI_CLASSIFIER_URL`, `TRAININGAI_HF_TOKEN`, `TRAININGAI_CLASSIFIER_TIMEOUT_MS`, `TRAININGAI_CLASSIFIER_MAX_IMAGE_BYTES`
- External dependencies: TrainingAI Oracle classifier or Hugging Face Space classifier

### /api/transfer-account-balance

- File: `api/transfer-account-balance.js`
- Methods: `POST`
- Purpose: Transfer PKN site balance from the authenticated user to another Pokoin account.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Recipient username/email/uid and PKN amount fields.
- Notable env vars: `FIREBASE_*`, `RESEND_API_KEY`
- External dependencies: Firebase Admin, email provider

### /api/unlock-silver

- File: `api/unlock-silver.js`
- Methods: `POST`
- Purpose: Unlock Silver status/features for the authenticated account.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Unlock request fields used by the client.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/upload-profile-picture

- File: `api/upload-profile-picture.js`
- Methods: `POST`
- Purpose: Optimize an uploaded profile picture and store it in R2.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: `imageBase64` required, max 6 MB source image.
- Notable env vars: `FIREBASE_*`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PROFILE_PICTURES_BUCKET`, `R2_PROFILE_PICTURES_PUBLIC_URL`
- External dependencies: Firebase Admin, Cloudflare R2, sharp

### /api/verify-email-signup

- File: `api/verify-email-signup.js`
- Methods: `POST`
- Purpose: Verify a pending email signup token, create/claim the Firebase user, and send welcome/notification emails.
- Auth: Public token verification.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Signup verification token and matching email/password verification fields.
- Notable env vars: `FIREBASE_*`, `RESEND_API_KEY`, `PENDING_SIGNUP_SECRET`
- External dependencies: Firebase Admin, email provider

### /api/wallet-auth/nonce

- File: `api/wallet-auth-nonce.js`
- Methods: `POST`
- Purpose: Create a nonce challenge for wallet sign-in.
- Auth: Public.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Wallet address and client challenge metadata.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/wallet-auth/verify

- File: `api/wallet-auth-verify.js`
- Methods: `POST`
- Purpose: Verify a signed wallet nonce and sign in/create the corresponding Firebase user.
- Auth: Public signed wallet challenge.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Wallet address, signature, nonce/session fields, and optional profile fields.
- Notable env vars: `FIREBASE_*`, `RESEND_API_KEY`
- External dependencies: Firebase Admin, email provider

### /api/wallet-link

- File: `api/wallet-link.js`
- Methods: `POST`
- Purpose: Link a wallet to the authenticated Firebase account.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Wallet address/signature/session fields.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/wallet-link/complete

- File: `api/wallet-link-complete.js`
- Methods: `POST`
- Purpose: Complete a wallet-link session from a signed wallet payload.
- Auth: Signed wallet-link session payload.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Wallet-link session id, address, signature, and profile fields.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/wallet-link/session

- File: `api/wallet-link-session.js`
- Methods: `POST`
- Purpose: Create a wallet-link session for an authenticated Firebase account.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- body: Wallet address and session metadata.
- Notable env vars: `FIREBASE_*`
- External dependencies: Firebase Admin

### /api/wpkn-exchange/:action

- File: `api/wpkn-exchange.js`
- Methods: `GET`, `POST`
- Purpose: Quote, request, and check native PKN/wPKN exchange flows.
- Auth: Required Firebase bearer token.
- Migration status: Hosted by `server/oracle-api-server.js`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
- path: `action` is `quote`, `request`, or `status`.
- body: `direction`, `amountIn`, `quoteId`, and `toAddress` depending on action.
- query: `requestId` optional for status.
- Notable env vars: `FIREBASE_*`, `POKOIN_RPC_URL`, `POKOIN_RESERVE_ADDRESS`, `POKOIN_RESERVE_PRIVATE_KEY`
- External dependencies: Firebase Admin, Pokoin RPC, BSC/Pancake helpers

