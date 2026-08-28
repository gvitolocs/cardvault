# Pokoin API Documentation

Base URL:

```text
https://pokoin.com
```

Local development:

```text
http://localhost:3000
```

## Authentication

Pokoin API authentication uses Firebase Authentication as the source of truth. After a user signs in with Firebase, the app exposes the Firebase ID token as the Pokoin bearer token.

Send it on protected requests:

```text
Authorization: Bearer <pokoin-bearer-token>
```

Tokens are short-lived and are refreshed by the Firebase SDK. The Flutter app wraps this behavior in `PokoinApiAuthService` and `PokoinApiClient`, so authenticated calls can attach the bearer token centrally until logout.

The extension token bridge always closes itself after returning an authenticated
token:

```text
GET /extension/auth-bridge
```

It posts a `pokoin-auth-token` message to `window.opener`/`window.parent` and
then calls `window.close()`. Browsers may keep manually opened tabs visible; in
that case the page shows a success state telling the user they can close it.

Normal auth pages only auto-close when opened with an extension marker:

```text
GET /auth?from=extension&closeOnAuth=1
```

`extension=1` is also accepted. When the user is authenticated, the page posts a
`pokoin-auth-complete` message to `window.opener`/`window.parent` and then calls
`window.close()`. Plain `/auth` keeps the standard redirect behavior.

Common errors:

```json
{ "error": "Missing Pokoin bearer token." }
```

```json
{ "error": "Firebase ID token has expired." }
```

## Auth Login

Validates the current Pokoin bearer token and returns safe login metadata.

```text
POST /api/auth-login
Authorization: Bearer <pokoin-bearer-token>
```

Response:

```json
{
  "ok": true,
  "auth": {
    "tokenType": "Bearer",
    "uid": "firebase-user-id",
    "email": "collector@example.com",
    "emailVerified": true,
    "expiresAt": "2026-05-21T09:50:00.000Z",
    "authTime": "2026-05-21T08:50:00.000Z"
  }
}
```

Logout is client-side: call Firebase sign out through `AuthService.signOut()`. There is no server logout endpoint because Pokoin does not store server sessions for this bearer-token flow.

JavaScript example:

```js
async function pokoinLogin(firebaseUser) {
  const token = await firebaseUser.getIdToken();
  const response = await fetch('https://pokoin.com/api/auth-login', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new Error(`Pokoin login failed: ${response.status}`);
  }
  return response.json();
}
```

## Extension Card Search

Searches Pokoin marketplace records from scraped card fields. This endpoint supports CORS and does not require auth.

```text
POST /api/extension-card-search
Content-Type: application/json
```

Request:

```json
{
  "name": "Mew",
  "collectorNumber": "232/091",
  "expansion": "Paldean Fates",
  "rarity": "Special Illustration Rare",
  "variation": "ex",
  "language": "en",
  "limit": 3
}
```

Response:

```json
{
  "query": "Mew ex 232/091 Paldean Fates",
  "source": "structured_fields",
  "language": "en",
  "matches": [
    {
      "cardId": "274416",
      "name": "Mew ex",
      "expansionName": "Paldean Fates",
      "collectorNumber": "Special Illustration Rare | 232/091",
      "previewImageUrl": "https://cdn.pokoin.com/previews/274416_mew-ex.jpg",
      "marketplacePath": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "marketplaceUrl": "https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "score": 16762.03
    }
  ]
}
```

The extension can also send `rarityAliases` for simplified UI chips such as
`illustration`; the backend expands those aliases while still blocking artist
labels like `Illus.` from search intent. More detail:
`docs/extension-card-search-api.md`.

## Marketplace Home

Returns the marketplace home snapshot and carousel sections.

```text
GET /api/marketplace-home
```

Response includes:

```json
{
  "cards": [
    {
      "id": "118502",
      "name": "Example Card",
      "artist": "Ryo Ueda",
      "illustrator": "Ryo Ueda"
    }
  ],
  "sections": {
    "recentlySeenIds": [],
    "bestSellerIds": [],
    "featuredIds": []
  }
}
```

`artist` and `illustrator` are optional display-only attribution metadata from
`marketplace_blueprint_artists`; they are not search/ranking signals.

Auth: none.

## Marketplace Cards

Returns searchable marketplace card and product rows.

```text
GET /api/marketplace-cards?query=lapras&limit=24&language=en
```

Common query parameters:

```text
query: free-text search
limit: 1-1000
language: two-letter language code
productType: optional product type filter
productSearchOnly: true/false
```

Rows may include optional `artist` and `illustrator` display metadata when the
blueprint has been enriched. These fields are not populated from search input
and should not be used as rarity, variation, query, or ranking signals.
Artist metadata comes from `marketplace_blueprint_artists`; non-primary
fallback sources may only validate or fill artists whose `normalized_artist`
already exists there, and unknown fallback artists must be reported rather than
inserted.

TCGdex structured card metadata is currently stored as DB-only enrichment in
`marketplace_blueprint_tcg_metadata`; it is not exposed by this endpoint.

Auth: none.

## Deck Card Version Lookup

Returns ranked marketplace card versions for structured decklist rows, using
card name, set code, and collector number instead of broad free-text search.

```text
GET /api/deck-card-version-lookup?name=Dreepy&setCode=TWM&collectorNumber=128&limit=8
POST /api/deck-card-version-lookup
```

The endpoint is for `/shard-review` deck imports and should rank exact
name + set code + collector number matches first, then same-name versions from
other expansions.

Auth: none.

## Limitless Expansion Blueprints

Returns the Limitless expansion-to-Pokoin blueprint mapping table populated from
approved/public Limitless card references where available.

```text
GET /api/limitless-expansion-blueprints?setCode=TWM&includeBlueprints=1
```

Rollout requires the additive schema:

```text
oracle-postgres/schema/016_limitless_expansion_blueprint_mapping.sql
```

Then populate from already-synced public Limitless decklist card rows:

```bash
node scripts/sync-limitless-expansion-blueprints.js --dry-run
node scripts/sync-limitless-expansion-blueprints.js --apply
```

This does not assume a full public Limitless card database API. If Limitless
approves or documents a card database endpoint later, the same tables/API can be
filled from that source.

## Marketplace Card Versions

Returns ordered version/navigation rows for card detail pages and full version
search.

```text
GET /api/marketplace-card-versions?cardId=118502&limit=100
```

Common query parameters:

```text
cardId: marketplace card/blueprint id
sameAsCardId: expansion-scoped version lookup anchor
cardSlug: human slug from the canonical public-number marketplace path
expansionName: optional expansion filter
query: optional version search text
limit: 1-1000
productType: optional product type filter
language: two-letter language code
```

Rows may include optional `artist` and `illustrator` display metadata from the
separate artist table.

Canonical card detail/share URLs use
`/marketplace/{lang}/cards/{blueprintId * 2}/{humanSlug}`. Example: Leafeon
`316600` resolves to
`/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions`.
Legacy `/marketplace/{lang}/cards/{blueprintId}-{slug}`,
`/marketplace/{lang}/cards/{blueprintId}`, and digit-only root short links still
resolve and canonicalize after the card payload loads.

Social preview crawlers are rewritten to `/api/marketplace-card-seo` for both
canonical marketplace paths and legacy root paths such as
`/124384/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6`. The SEO response
must include server-rendered `og:image`, `og:url`, and Twitter tags because the
Flutter SPA cannot update metadata before chat apps unfurl the URL. Verify with:

```bash
curl -A "Discordbot/2.0" https://pokoin.com/124384/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6
curl -A "Slackbot-LinkExpanding 1.0" https://pokoin.com/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions
curl -A "Twitterbot/1.0" https://pokoin.com/marketplace/en/cards/633396/common-fan-rotom-085-131-prismatic-evolutions
```

Auth: none.

## Marketplace Artist Cards

Returns cards grouped by artist/illustrator attribution from
`marketplace_blueprint_artists`. This endpoint is for display and collection
grouping only; artist names must not be treated as autocomplete/search ranking
signals.

```text
GET /api/marketplace-artist-cards?artistSlug=ryo-ueda&limit=240
```

Common query parameters:

```text
artistSlug: URL slug derived from normalized_artist
artist: optional raw artist name fallback
limit: 1-1000
```

Response:

```json
{
  "artist": {
    "name": "Ryo Ueda",
    "illustrator": "Ryo Ueda",
    "normalizedArtist": "ryo ueda",
    "slug": "ryo-ueda",
    "cardCount": 360
  },
  "profile": {
    "displayName": "Ryo Ueda",
    "summary": "Short sourced summary when available.",
    "bio": "PocketMonsters profile text when verified.",
    "imageUrl": "https://pokoin.com/card-images/artist-profiles/ryo-ueda.png",
    "sourceImageUrl": "https://media.pocketmonsters.net/staff/7159/main.png",
    "imageObjectKey": "artist-profiles/ryo-ueda.png",
    "pocketmonstersUrl": "https://www.pocketmonsters.net/staff/view/7159",
    "pocketmonstersId": "7159",
    "bulbapediaUrl": "https://bulbapedia.bulbagarden.net/wiki/Ryo_Ueda",
    "bulbapediaTitle": "Ryo Ueda",
    "sourceName": "PocketMonsters.Net + Bulbapedia",
    "sourceUrl": "https://www.pocketmonsters.net/staff/view/7159"
  },
  "cards": [
    {
      "card_id": "118502",
      "name": "Example Card",
      "expansion_name": "Example Expansion",
      "expansion_number": "001",
      "artist": "Ryo Ueda",
      "illustrator": "Ryo Ueda"
    }
  ]
}
```

Flutter consumes this endpoint for `/marketplace/{lang}/artists/{artistSlug}`
and `/collection/artists/{artistSlug}`. The marketplace artist page follows the
versions-page gallery pattern; the collection artist page uses the profile
collection grid where owned cards are full color and missing cards are dimmed
and grayscale.

Artist profile metadata comes from the separate
`marketplace_artist_profiles` table, keyed by `normalized_artist`. Profile
images prefer Pokoin R2 URLs served through the same-origin
`/card-images/artist-profiles/...` Worker proxy when cached; source image URLs
are returned only as provenance/fallback. Bulbapedia references are displayed
with source links and CC BY-NC-SA attribution. Profile text is display-only
metadata and must not be fed into marketplace search, autocomplete, rarity
parsing, or ranking.

When a real profile portrait is missing or the cached source image is a known
placeholder, `profile.generatedProfileImage` may describe a generated fallback
avatar cropped from one card illustrated by the artist. These avatars use
top-center square crops from full-size card art and keep source card/provenance
metadata for UI attribution.

Auth: none.

## Marketplace Hot Blueprints

Returns hot marketplace blueprint rows and rolling interaction counts.

```text
GET /api/marketplace-hot-blueprints?includeCards=1&limit=100
```

When card payloads are included, rows may include optional `artist` and
`illustrator` display metadata. Artist fields are attribution only and do not
drive hot scores.

Auth: none.

## Marketplace Competitive

Returns Limitless-backed competitive tournament, standings, and pairing data for
the competitive marketplace page.

```text
GET /api/marketplace-competitive?includeGames=1&game=PTCG&limit=50
GET /api/marketplace-competitive?tournamentId=<limitless-id>
```

Auth: none.

Rollout requires data, not just the frontend route. Before expecting
`/marketplace/competitive` to show competitive data, apply the non-destructive
Oracle/Postgres schema:

```text
oracle-postgres/schema/014_limitless_competitive.sql
```

Then run the Limitless sync after a dry-run or small test:

```bash
node scripts/sync-limitless-competitive.js --dry-run --game=PTCG --max-tournaments=10
node scripts/sync-limitless-competitive.js --apply --game=PTCG --max-tournaments=100
```

Public Limitless imports may include games, tournaments, standings, and pairings
where the API allows. Restricted decklist endpoints may require Limitless
approval and `LIMITLESS_API_KEY`; document missing decklist access as a blocker
instead of assuming those payloads are available.

After rollout, verify `https://api.pokoin.com/healthz`,
`https://api.pokoin.com/api/marketplace-competitive`,
`https://pokoin.com/marketplace/competitive`, and the trophy icon marketplace
route. The competitive API should be non-empty before the page is considered live
unless an intentional empty-state rollout was approved.

## Marketplace Blueprint Price

Returns the current public PKN floor price for one marketplace blueprint/card ID.
The price is sourced from the lowest active seller listing in
`marketplace_blueprint_price_summary`.

```text
GET /api/marketplace-blueprint-price?blueprintId=274416
```

`cardId` is accepted as an alias for `blueprintId`.

This endpoint is public and must be present in both `vercel.json` rewrites and
`deploy-pokoin-web.sh` packaging. If it is routed but not copied to
`build/web/api`, production clients may receive the Flutter HTML shell instead
of JSON.

Response:

```json
{
  "blueprint_id": "274416",
  "card_id": "274416",
  "price_pkn": 1200,
  "currency": "PKN",
  "unit": "PKN",
  "source": "lowest_listing",
  "listing_count": 2,
  "listed_quantity": 3,
  "updated_at": "2026-05-21T08:00:00.000Z"
}
```

When no active PKN listing price exists, the endpoint returns `404` with a null
price shape:

```json
{
  "blueprint_id": "274416",
  "card_id": "274416",
  "price_pkn": null,
  "currency": "PKN",
  "unit": "PKN",
  "source": null,
  "listing_count": 0,
  "listed_quantity": 0,
  "updated_at": null,
  "error": "No active PKN listing price found for this blueprint."
}
```

Auth: none. This matches the public marketplace home, catalog, and active
listing reads that already expose active seller pricing.

This endpoint supports CORS preflight for browser-extension price enrichment.

## Social Autoposter

Posts Pokoin marketplace copy to Telegram and X from server-side credentials.
The endpoints support `dryRun` and should be tested that way before live posting.
By default they attempt to use the dedicated peer2 social copy agent when
`SOCIAL_AGENT_TOKEN` is configured, then fall back to deterministic copy if the
agent is unavailable.

Manual post:

```text
POST /api/social-autopost
Content-Type: application/json
x-pokoin-social-secret: <SOCIAL_AUTOPOST_SECRET>
```

```json
{
  "targets": ["telegram", "x"],
  "message": "Hot on Pokoin: Rare Leafeon is trending today.",
  "cardId": "316600",
  "useAgent": true,
  "dryRun": true
}
```

Hot-card post:

```text
GET /api/social-autopost/hot-card?targets=telegram,x&window=24h&dryRun=true
Authorization: Bearer <SOCIAL_AUTOPOST_SECRET>
```

Generate copy only without posting:

```text
POST /api/social-post-agent
Content-Type: application/json
x-pokoin-social-secret: <SOCIAL_AUTOPOST_SECRET>
```

Auth: required shared social secret, `CRON_SECRET` bearer, or existing
marketplace debug/admin Firebase bearer token.

Required server env:

```text
SOCIAL_AUTOPOST_SECRET
SOCIAL_AGENT_ENDPOINT
SOCIAL_AGENT_TOKEN
SOCIAL_AGENT_TIMEOUT_MS
TELEGRAM_BOT_TOKEN
TELEGRAM_CHANNEL_ID
X_ACCESS_TOKEN
X_OAUTH2_ACCESS_TOKEN
X_OAUTH2_REFRESH_TOKEN
X_BEARER_TOKEN
X_API_KEY
X_API_SECRET
X_ACCESS_TOKEN_SECRET
```

`SOCIAL_AGENT_ENDPOINT` defaults to the dedicated peer2 social route
`http://130.162.242.213:8787/social-post`. Do not point it at the support
chatbot `/chat` path. The social agent receives explicit instructions to use
Pokoin brand voice, include canonical URLs, respect the X length limit, and avoid
hallucinating prices/listings.

`X_ACCESS_TOKEN` or `X_BEARER_TOKEN` must be a user-context OAuth 2.0 token for
X API v2 with `tweet.write`, `tweet.read`, `users.read`, and `media.write`;
app-only bearer tokens are not sufficient for creating posts. `CRON_SECRET` is
optional for future scheduled calls. See `workflows/social-autoposter-workflow.md`
for setup steps.

OAuth 1.0a X credentials are also supported with `X_API_KEY`, `X_API_SECRET`,
`X_ACCESS_TOKEN`, and `X_ACCESS_TOKEN_SECRET`.

## Pokontact Assistant

Answers Pokoin assistant chat requests. The endpoint is public, but a Firebase
bearer token may be included to attach verified user context.

```text
POST /api/pokoin-assistant
Content-Type: application/json
Authorization: Bearer <optional-pokoin-bearer-token>
```

Request:

```json
{
  "message": "most expensive charizard card",
  "messages": [{ "role": "user", "text": "what is the most expensive charizard card?" }],
  "page": "https://pokoin.com/marketplace/en",
  "pageContext": {
    "url": "https://pokoin.com/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions",
    "path": "/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions",
    "title": "Marketplace card detail",
    "cardId": "316600",
    "cardTitle": "Rare Leafeon 005 131 Prismatic Evolutions"
  },
  "username": "guest"
}
```

`messages` should be bounded by the client. The current Flutter widget sends the
latest 12 non-empty chat messages. `pageContext` is optional but enables current
card/page follow-ups such as "this card" and short marketplace follow-ups.

Marketplace/card/analytics questions are grounded in Oracle marketplace tables
before any Oracle-hosted Pokontact LLM call:

- active listing, highest-price, floor-price, and best-deal questions read
  `marketplace_user_listings` and `marketplace_blueprint_price_summary`;
- direct card suggestions resolve through `marketplace_search_candidates` and
  `marketplace_card_urls`;
- popularity/analytics answers read `marketplace_hot_blueprints`.

The assistant must not invent prices, active listings, or popularity. If Oracle
data is missing, the response says the marketplace data is unavailable or that no
active listing was found. Price/popularity answers are marketplace context, not
financial advice.

Response:

```json
{
  "reply": "I checked active Pokoin marketplace listings...",
  "intent": "marketplace",
  "actions": [
    {
      "type": "navigate",
      "path": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "label": "Open Mew ex"
    }
  ],
  "serviceDelivery": {
    "ok": true,
    "source": "marketplace-grounding",
    "provider": "pokoin-marketplace-tool",
    "model": "deterministic"
  },
  "assistant": "Pokontact"
}
```

Structured `navigate` actions use safe internal Pokoin paths only. The Flutter
client opens those paths in the current tab and records the same path for the
current assistant browser session through `/api/user-current-page`.

## Assistant Current Page

Stores or reads the current internal Pokoin page for a browser/session so
assistant-driven card opens can target the user's current tab.

```text
POST /api/user-current-page
Content-Type: application/json
Authorization: Bearer <optional-pokoin-bearer-token>
```

Request:

```json
{
  "sessionId": "flutter-12345678-1",
  "path": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
  "source": "assistant-navigate"
}
```

`path` must be a safe internal path. Absolute `https://pokoin.com/...` URLs are
normalized to paths; external URLs and protocol-relative URLs are rejected.

Identity contract: if the browser has a signed-in Firebase user, the assistant
client must send a fresh Firebase ID token for this request. Do not reuse a
long-lived cached assistant `_bearerToken` for polling because Firebase ID tokens
expire and rotate while tabs remain open. If there is no signed-in user, omit the
Authorization header and use anonymous session scope. If an Authorization header
is present but Firebase Admin rejects it, treat that as an authentication error
and investigate/refresh the client token; do not silently downgrade the request
to anonymous identity.

Read the latest page:

```text
GET /api/user-current-page?sessionId=flutter-12345678-1
```

Response:

```json
{
  "page": {
    "sessionId": "flutter-12345678-1",
    "userUid": "",
    "path": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
    "source": "assistant-navigate",
    "updatedAt": "2026-05-24T10:00:00.000Z"
  },
  "sessionId": "flutter-12345678-1",
  "authenticated": false
}
```

## CardTrader Seller Connection

Seller CardTrader APIs require a Pokoin bearer token and use the verified
Firebase UID as the seller identity. Raw CardTrader tokens are accepted only on
connect and are never returned by any response.

Required server env:

```text
CARDTRADER_TOKEN_ENCRYPTION_KEY
```

The key must decode to exactly 32 bytes and is used for AES-256-GCM encryption
of the CardTrader token and webhook `shared_secret` before Firestore storage.

Connect or replace token:

```text
POST /api/cardtrader-connect
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Request:

```json
{ "token": "<cardtrader-api-token>" }
```

The backend validates the token with:

```text
GET https://api.cardtrader.com/api/v2/info
Authorization: Bearer <cardtrader-api-token>
```

Response:

```json
{
  "ok": true,
  "status": {
    "connected": true,
    "provider": "cardtrader",
    "metadata": {
      "app": { "id": "app-id", "name": "App name" },
      "user": { "id": "user-id", "email": "seller@example.com" },
      "seller": { "id": "seller-id", "name": "Seller name" },
      "scopes": []
    },
    "connectedAt": "2026-05-22T08:00:00.000Z",
    "lastValidatedAt": "2026-05-22T08:00:00.000Z",
    "updatedAt": "2026-05-22T08:00:00.000Z"
  }
}
```

Read safe status:

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

Clean linked listings:

```text
POST /api/cardtrader-clean-listings
Authorization: Bearer <pokoin-bearer-token>
```

This inactivates only marketplace listings owned by the authenticated seller
whose source fields indicate CardTrader linkage (`source='cardtrader'` or a
CardTrader `sourceListingId`). Native Pokoin listings are not touched.

Response:

```json
{
  "ok": true,
  "cleanedCount": 3,
  "listingIds": ["listing-id"],
  "cardIds": ["274416"]
}
```

Safe inventory import dry-run:

```text
POST /api/cardtrader-import-dry-run
Authorization: Bearer <pokoin-bearer-token>
```

This decrypts the seller token server-side, reads CardTrader
`GET /products/export`, and returns counts plus a small redacted sample. It does
not create, update, increment, or delete Pokoin/CardTrader inventory.

Daily CardTrader listing snapshot refresh:

```text
GET|POST /api/cardtrader-daily-listings-refresh
Authorization: Bearer <admin diagnostic secret>
```

This endpoint is a guarded manual diagnostic path only. The scheduled daily
CardTrader public listing ingestion runs on the Oracle/peer4 host with
`scripts/run-cardtrader-daily-market-refresh.sh`, not Vercel Cron. The wrapper
first runs `scripts/refresh-cardtrader-market-listings.js`, which uses the global
CardTrader marketplace API token, calls `GET /api/v2/marketplace/products` by
blueprint or expansion, refreshes Oracle `cardtrader_market_listing_snapshots`,
archives missing rows in `cardtrader_market_listing_removed_history` with
`removed_day = current_date - 1` by default, and projects global market rows into
the existing card graph path via `marketplace_price_observations` sources
`cardtrader_snapshot` and `cardtrader_removed_sale`. After that succeeds, the
wrapper runs `scripts/refresh-cardtrader-blueprint-listing-cache.js` to derive
`cheapest_homepage_cache_blueprint`, the compact one-row-per-blueprint projection
used by marketplace home/catalog tile payloads for the cheapest eligible Zero +
1-Day Ready price from the daily backend listings cache/import. That projection
is a durable Oracle read model, not the live endpoint cache. If production still
refreshes `cardtrader_blueprint_listing_cache`, that is the legacy physical table
name for this projection until a migration renames it. Card detail seller rows
and detailed CardTrader listing metadata keep using the live parser. No Pokoin
user or connected seller is involved in this global market analytics refresh.

Useful test controls:

```text
?dryRun=1&blueprintId=316600&maxBlueprints=25&maxProducts=250
```

Required Oracle/peer4 job env includes `CARDTRADER_AUTH_TOKEN` or the documented
fallback `CARDTRADER_API_TOKEN`, plus `MARKETPLACE_DATABASE_URL`. The manual
diagnostic endpoint also requires one of `CARDTRADER_DAILY_LISTINGS_SECRET`,
`CARDTRADER_DAILY_REFRESH_SECRET`, or `CRON_SECRET`. Seller connect/import
dry-runs remain separate and still use encrypted per-seller tokens with
`GET /products/export`. The Oracle/peer4 env must contain the CardTrader token
for the daily job even if Vercel production also has a token for live
compatibility routes.

CardTrader live listings for card pages:

```text
GET /api/cardtrader-live-listings?blueprintId=316600
GET /api/cardtrader-live-listings?cardId=248856
```

This endpoint answers which CardTrader listings currently have the requested
card. It calls CardTrader live through the trusted server global token
(`CARDTRADER_AUTH_TOKEN`, falling back to `CARDTRADER_API_TOKEN`) and does not
write Oracle or any database. It uses CardTrader
`GET /api/v2/marketplace/products?blueprint_id=:id`; CardTrader returns an object
keyed by blueprint id with the cheapest current products.

When this path is served by a Vercel compatibility route, Vercel production must
include `CARDTRADER_AUTH_TOKEN` or `CARDTRADER_API_TOKEN`. Do not rely on the
peer4 env file for Vercel-hosted live calls, and do not expose either token to
clients.

`CARDTRADER_AUTH_TOKEN` is the preferred token name for live listing reads,
daily marketplace refreshes, and guarded CardTrader buy-through. `CARDTRADER_API_TOKEN`
remains a legacy read/import fallback so older jobs do not break, but new
configuration should use `CARDTRADER_AUTH_TOKEN`.

`blueprintId` is a direct CardTrader blueprint ID. `cardId` is a Pokoin card ID;
numeric values are resolved through Oracle card data when available and otherwise
treated as the CardTrader blueprint ID because Pokoin card IDs currently map to
CardTrader blueprints. Responses have a short in-process/HTTP cache and include
safe public product/listing metadata only. By default the route returns every
row CardTrader returns for the blueprint. Clients may pass `limit` to request a
smaller result set; explicit limits are capped at a high safety ceiling, not the
old production default of 25.

The live in-process cache is a per-Node-process `Map`, not Oracle storage. Cache
keys are `cardtrader:<resolvedBlueprintId>:<language-or-empty>:<limit-or-all>`,
entries live for 45 seconds, and the map is capped at 100 entries. Expired
entries are pruned on reads/writes, and overflow removes the oldest
insertion-order keys. There is no shared cache across serverless instances,
database persistence, webhook invalidation, or admin invalidation endpoint; a
process restart clears it. The endpoint also sends
`Cache-Control: public, max-age=30, s-maxage=60`, which is separate browser/CDN
or proxy caching. Explicit `limit` values are clamped to `1..1000` and only cap
the response after CardTrader is fetched.

Live listing rows include inferred `shippingMode` and `shippingLabel` fields.
`shippingMode` is one of `one_day_ready`, `zero`, or `normal`. CardTrader does
not expose a direct shipping-type field in this payload, so the route uses this
ordered inference:

1. `one_day_ready` only when explicit seller/listing text matches `1-Day Ready`
   or `One Day Ready`.
2. `zero` when `can_sell_via_hub` or `can_sell_sealed_with_ct_zero` is present
   and the listing is not one-day-ready.
3. `normal` otherwise.

`max_sellable_in24h_quantity` alone must not classify a listing as
`one_day_ready`, and sellers are not classified as `zero` solely because they are
professional accounts. Regression examples for blueprint `248856`: EeveeRaff and
Mikebarocco are `one_day_ready`; Lolimpodelnerd, Laconteacag, and Card Universe
are `zero`; Tcg-mapro54_cardsita is `normal`. This metadata is returned only in
the live response and is not written to Oracle or any database.

CardTrader historical/daily listing snapshots:

```text
GET /api/cardtrader-blueprint-listings?blueprintId=316600
GET /api/cardtrader-blueprint-listings?cardId=274416
```

This read endpoint is hosted by the Oracle/peer4 API service and can also run as
a Vercel compatibility route while `/api/*` traffic is still cut over. `blueprintId`
matches `blueprint_id` or `cardtrader_blueprint_id`; `cardId` matches
`pokoin_card_id` and, when numeric, also matches the CardTrader blueprint columns.
Use `limit`, `page`, or `cursor` to paginate large listing sets.

The endpoint reads Oracle `cardtrader_market_listing_snapshots` only. It must not
call CardTrader live; use `/api/cardtrader-live-listings` for on-demand card page
lookups. The daily Oracle ingestion job refreshes current snapshots and archives
missing listings in `cardtrader_market_listing_removed_history`; this read
endpoint only returns the latest safe metadata derived from those tables.
Marketplace tiles/cards read `cheapest_homepage_cache_blueprint` for the
cheapest eligible Zero + 1-Day Ready price derived from the daily backend
listings cache/import and must not make live CardTrader API calls during tile
rendering. This durable projection is separate from
`cardtrader_market_listing_snapshots` and from the live route's 45-second
in-memory response cache. If SQL still reads
`cardtrader_blueprint_listing_cache`, that is the legacy physical table name for
this projection until a migration renames it. Card detail seller listings
continue to use the live CardTrader route so seller rows, comments, flags, and
prices come from the detailed parser.

Response fields include safe public listing metadata: external listing/product
ids, CardTrader blueprint id, Pokoin card id when mapped, price/currency,
quantity, condition, language, sanitized `properties` and `rawMetadata`, public
seller identity fields when present, first/last seen timestamps, import/update
timestamps, and pagination metadata. Responses must not include CardTrader API
tokens, seller tokens, webhook shared secrets, encrypted secret envelopes, raw
headers, or sensitive raw metadata keys.

Auth: none while the payload remains limited to public listing metadata. Flutter
may call this Pokoin API from card detail pages to show CardTrader
listings/metadata, but Flutter must not call CardTrader directly.

## Marketplace Autocomplete

Returns ranked search suggestions and supports debug details for authorized accounts.

```text
POST /api/marketplace-autocomplete
Content-Type: application/json
```

Request:

```json
{
  "search_term": "mew",
  "result_limit": 8,
  "pool_limit": 1000,
  "search_language": "en"
}
```

This endpoint supports CORS preflight for browser-extension fallback search.

Auth: none for normal autocomplete. Debug fields require:

```text
Authorization: Bearer <pokoin-bearer-token>
```

When a valid bearer token is present, autocomplete can use the verified Firebase
UID for personalization signals from Oracle marketplace events. Operators keep
Oracle's minimal Firebase user dimension current with:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/sync-firebase-users-to-oracle.js --limit=25
node scripts/sync-firebase-users-to-oracle.js --apply --limit=all
```

The sync stores UID, safe profile metadata, provider IDs, disabled/email
verification flags, and sync timestamps in `marketplace_firebase_users`. It does
not store bearer tokens, refresh tokens, passwords, or Firebase custom claims.

## Searchbar Token Prediction

Returns only the top predicted Pokemon/card-name tokens for the active typed
fragment. Use this for Flutter ghost autocomplete and browser extension token
identification before calling heavier search endpoints.

```text
POST /api/searchbar-token-predict
GET /api/searchbar-token-predict?query=p&search_language=en&limit=5
```

Request:

```json
{
  "query": "mewt",
  "search_language": "en",
  "limit": 5
}
```

Response:

```json
{
  "ok": true,
  "endpoint": "/api/searchbar-token-predict",
  "query": "mewt",
  "fragment": "mewt",
  "normalized_fragment": "mewt",
  "search_language": "en",
  "limit": 5,
  "predictions": [
    {
      "display_token": "Mewtwo",
      "normalized_token": "mewtwo",
      "confidence": 94,
      "score": 140000,
      "source_rank": 1,
      "language": "en",
      "matched_prefix": "mewt",
      "card_count": 24,
      "ids_count": 24,
      "representative_card_ids": ["150"]
    }
  ],
  "meta": {
    "source": "supabase_postgres",
    "model": "marketplace_card_name_tokens",
    "duration_ms": 12
  }
}
```

This endpoint reads only Supabase `marketplace_card_name_tokens`; it does not
return full rows, `search_context`, context labels, prices, listings, analytics,
or Oracle-hydrated card data. The default payload is intended to stay under 2KB.
If the Supabase token table is unavailable, callers should treat an error or an
empty `predictions` list as "no token prediction" and continue with full search.

Normalization follows the backend compact token model: apostrophes and curly
apostrophes, underscores, hyphens/dashes, dots, brackets, whitespace, slashes,
gender symbols, and diacritics collapse out of `normalized_token`; ampersand
forms are compacted through `tagteam` where applicable. Ranking combines prefix
quality with `row_count`/`card_ids` popularity, so broad one-character input like
`p` can favor high-card-count tokens such as Pikachu, while longer prefixes such
as `par` favor the tighter textual match.

Autocomplete uses the requested `language` for localized card names and for the
predictive ngram/chunk model. `marketplace_name_ngrams` and
`marketplace_query_chunk_events` are keyed by language, and chunk-frequency
ranking boosts are only read from the selected language. If a language has no
chunk event history, the boost is neutral (`0`) rather than borrowing English
analytics; English is only used when the request language itself is cleaned to
the default `en`.

When `SUPABASE_NAME_INDEX_DATABASE_URL` or server-side `SUPABASE_DB_URL` is
configured on the backend, autocomplete may use Supabase as a derived
short-prefix card-name index for fast candidate IDs/labels. Supabase does not
serve full card details, listings, prices, analytics, or user data; Oracle
remains the source of truth and hydrates the returned marketplace rows. If the
Supabase name index is absent or unhealthy, the endpoint falls back to the
existing Oracle replica paths and briefly circuits the optional tier to avoid
probing a missing table on every keypress.

## Searchbar Cards

Stable wrapper for searchbar experiments and benchmarks. It reuses marketplace
autocomplete ranking but always returns a structured object response.

```text
POST /api/searchbar-cards
GET /api/searchbar-cards?query=pikachu&search_language=en&limit=20&pool_limit=5000
```

Request:

```json
{
  "query": "mew ex 216",
  "search_language": "en",
  "limit": 20,
  "pool_limit": 5000,
  "previous_search_context": null,
  "debug": false,
  "mode": "benchmark_step"
}
```

`/api/searchbar-cards` uses the same optional Supabase name-index candidate tier
as autocomplete. Supabase is only a derived ID/label fallback for broad name
prefixes; Oracle remains authoritative for hydration and ranking, and Oracle
replica paths are used when the Supabase tier is absent, empty, slow, or
unhealthy.

Response includes `rows`, `search_context`, and `meta`. `meta` may expose
candidate counts, candidate-ID ladder metadata, `search_path`/`searchPath`,
`poolSource`, replica/fallback fields, and timing fields such as candidate,
analytics, and rank durations when debug output is enabled. Use
`scripts/benchmark-searchbar-api.js` for char-by-char latency and quality runs.

`/api/searchbar-cards` remains the full pool/searchbar wrapper. Flutter calls
`/api/searchbar-token-predict` separately for fast ghost text, then lets the full
`/api/searchbar-cards` or `/api/marketplace-autocomplete` pool continue in the
background for rows, IDs, and context labels.

When `MARKETPLACE_PREDICTIVE_POOL_ENABLED=1`, `meta.predictive` may also include
the dynamic prediction contract: `model`, provisional `predicted_tokens`
(`normalized`, `display`, `confidence`, `source_rank`, `language`, and
representative IDs), per-source route/status entries, and `failed_source_count`.
These fields are diagnostic metadata for the backend-ranked 5000-ID pool; a high
confidence value is a ranking boost, not a final card-name lock.

## Marketplace Listings

Reads and writes user seller listings.

Public active listings:

```text
GET /api/marketplace-listings?cardId=274416&limit=50
```

Seller-owned listings require auth and must match the token UID:

```text
GET /api/marketplace-listings?sellerUid=<firebase-uid>
Authorization: Bearer <pokoin-bearer-token>
```

Create listing:

```text
POST /api/marketplace-listings
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Request:

```json
{
  "cardId": "274416",
  "sellerName": "Pokoin seller",
  "sellerCountry": "EU",
  "condition": "NM",
  "language": "EN",
  "pricePkn": 1200,
  "quantityAvailable": 1,
  "shippingAvailable": true,
  "reserveAvailable": false,
  "nftAvailable": false
}
```

Update listing:

```text
PATCH /api/marketplace-listings?id=<listing-id>
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Only the owning seller UID can update the listing.

`reserveAvailable` is a public Reserve tag for cards available in the Pokoin
reserve. It is distinct from `shippingAvailable` and should not be used as a
shipping flag. `nftAvailable` marks listings sold as NFT-backed inventory; UI
labels should use `NFT`.

Reserve listings are role-gated on the API. Creating a listing with
`reserveAvailable: true`, a reserve source such as `reserve`, `pokoin_reserve`,
or `pknreserve`, or updating an existing reserve listing requires the Firebase
reserve role. Normal authenticated sellers can still create non-reserve listings.
The backend recognizes the role from Firebase custom claims and `users/{uid}`
profile fields: `reserve: true`, `isReserve: true`, `hasReserveAccess: true`,
`role: "reserve"`, or `roles` containing `reserve`.

Assign the role with a dry-run-first admin script:

```bash
node scripts/set-firebase-reserve-role.js --identifier=pknreserve
node scripts/set-firebase-reserve-role.js --identifier=pknreserve --apply
```

The script applies only when `pknreserve` resolves to exactly one Auth/Profile
user. After applying, the account must sign out/in or refresh its Firebase ID
token before reserve custom claims appear on new API requests.

## Marketplace Orders

Creates a paid marketplace order from cart listing snapshots. This endpoint is
the server-side fulfillment point for cart checkout; it verifies the buyer token,
checks PKN balance, decrements each active Oracle listing, writes a paid
Firestore `orders/{orderId}` document, credits seller balances, and then handles
the selected fulfillment mode.

```text
POST /api/marketplace-orders
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Request:

```json
{
  "items": [
    {
      "listingId": "listing-uuid",
      "sellerUid": "firebase-seller-uid",
      "sellerName": "Pokoin seller",
      "quantity": 2,
      "unitPricePkn": 1200,
      "totalPricePkn": 2400,
      "reserveAvailable": true,
      "nftAvailable": true,
      "card": { "id": "274416", "name": "Mew ex" }
    }
  ],
  "subtotalPkn": 2400,
  "taxPkn": 192,
  "shippingPkn": 0,
  "totalPkn": 2592,
  "fulfillmentMode": "nft_only"
}
```

`fulfillmentMode` defaults to `physical`. Physical checkout keeps the current
temporary shipping amount from the Flutter cart/checkout UI and continues seller
notification and CardTrader buy-through behavior. `nft_only` is accepted only
when every item has `nftAvailable` or `reserveAvailable`; server-side shipping is
forced to `0`, seller physical fulfillment notifications are skipped, CardTrader
buy-through is skipped, and owned NFT entries are written to
`user_card_collections` with `ownershipType: "nft"` and
`physicalShippingStatus: "not_requested"`.

Response includes the paid order and a best-effort seller notification result:

```json
{
  "ok": true,
  "order": {
    "id": "order-id",
    "status": "paid",
    "paymentStatus": "paid",
    "fulfillmentStatus": "awaiting_seller_confirmation"
  },
  "sellerNotification": {
    "ok": true,
    "sellerNotifications": []
  }
}
```

### NFT Physical Shipping Requests

NFT owners can later request physical cards from the profile NFT page. This is a
guarded intent endpoint only: it writes `nft_shipping_requests` and marks the
collection item as requested. It does not charge PKN and does not call any
external fulfillment API.

```text
POST /api/marketplace-orders?action=nft-shipping-request
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

Request one NFT with `collectionItemId` or many with `collectionItemIds`:

```json
{
  "collectionItemIds": ["collection-doc-id"],
  "shippingAddress": {
    "name": "Ash Ketchum",
    "line1": "1 Pallet Road",
    "city": "Pallet Town",
    "postalCode": "001",
    "country": "JP"
  },
  "notes": "Hold for ops quote"
}
```

Remaining ops blocker: a real fulfillment/label provider and any shipping charge
collection must be added later before requests can leave `pending_ops_review`.

Seller sale notification behavior:

- Emails are sent only after the order is paid and listings have been decremented.
- Items are grouped by `sellerUid`, so one seller gets one email per order even
  if multiple cards from that seller were in the cart.
- The sender is always `market@pokoin.com`; verify this sender/domain with the
  email provider before enabling production sends.
- Delivery uses `RESEND_API_KEY` through the shared email helper. Missing email
  configuration is logged and recorded as skipped, but payment fulfillment still
  succeeds.
- Idempotency is durable in Firestore via
  `order_seller_sale_notifications/{orderId}__{sellerUid}` markers, so retries
  do not resend duplicate seller emails.

## Forum APIs

Forum reads are public:

```text
GET /api/forum
GET /api/forum?categoryId=general
GET /api/forum?topicId=<topic-id>
```

Forum writes require auth:

```text
POST /api/forum-create-topic
POST /api/forum-create-post
POST /api/forum-upload-media
Authorization: Bearer <pokoin-bearer-token>
Content-Type: application/json
```

## Profile And Account APIs

These APIs require a Pokoin bearer token:

```text
POST /api/ensure-username
POST /api/signup-notification
POST /api/cache-google-profile-picture
POST /api/upload-profile-picture
POST /api/remove-profile-picture
POST /api/search-recipient-emails
POST /api/transfer-account-balance
POST /api/request-pkn-withdraw
POST /api/create-pkn-checkout-session
POST /api/marketplace-orders
POST /api/cardtrader-connect
GET /api/cardtrader-status
POST /api/cardtrader-disconnect
POST /api/cardtrader-clean-listings
POST /api/cardtrader-import-dry-run
POST /api/top-up-account-balance
POST /api/wpkn-exchange
POST /api/unlock-silver
```

Deployment note: every route listed here, plus public marketplace APIs such as
`/api/marketplace-card-seo`, `/api/marketplace-blueprint-price`,
`/api/marketplace-competitive`, `/api/crypto-pkn-purchase/:action`, and
`/api/crypto-pkn-sale/:action`, must be copied by `deploy-pokoin-web.sh` into
`build/web/api` with server helpers copied to `build/web/server`. Missing
packaging commonly surfaces as `405`, empty response, or HTML where Flutter
expects JSON.

Use `Content-Type: application/json` for JSON bodies. The UID is always read from the verified bearer token, not from the request body.

### PKN Stripe Checkout

`POST /api/create-pkn-checkout-session` starts a Stripe Checkout payment for a fixed PKN package and returns:

```json
{ "id": "cs_...", "url": "https://checkout.stripe.com/..." }
```

The request requires a valid bearer token and a package payload such as:

```json
{
  "pknAmount": 5000,
  "fiatCents": 2500,
  "lookupKey": "pkn_collector_5000_pkn_2500_eur"
}
```

The endpoint expects `STRIPE_SECRET_KEY`, Firebase Admin env vars, and `PUBLIC_SITE_URL` in the deployed environment. `STRIPE_WEBHOOK_SECRET` is required by `POST /api/stripe-webhook`, which credits completed Checkout sessions. If the function fails before the handler runs, Vercel may return plain text instead of JSON; client code should show a generic checkout availability message in that case.

## Wallet Link APIs

Wallet sign-in starts without Firebase auth:

```text
POST /api/wallet-auth/nonce
POST /api/wallet-auth/verify
```

Linking a wallet to an existing account requires auth:

```text
POST /api/wallet-link
POST /api/wallet-link/session
Authorization: Bearer <pokoin-bearer-token>
```

Completing a wallet-link session uses the signed wallet session payload:

```text
POST /api/wallet-link/complete
```

## Operational Notes

- Protected endpoints validate tokens with Firebase Admin in `api/_firebase.js`.
- Required Vercel env vars are `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, and optionally `FIREBASE_STORAGE_BUCKET`.
- Do not log bearer tokens.
- Do not send user-supplied UID as authorization. Use the decoded token UID.
