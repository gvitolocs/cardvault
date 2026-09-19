# Pokoin HTTP API — React / JavaScript contract

**Audience:** a future React (Next.js) public website, the current Flutter
Android/iOS app, browser extensions, and any other first-party client.

**Locked decision (Honcho 2026-08-28, Codevira D00000B):** CardVault stays
**API-first**. The public marketplace on `pokoin.com` will move to React/JS.
Flutter remains the native Android/iOS app, not the long-term public web
renderer. Do not rewrite the whole Flutter repo; strangler-replace home,
search, and card detail first. `home_screen.dart` (~7.5k lines) and
`card_detail_screen.dart` (~8.7k lines) are the Flutter-web bottleneck
(CanvasKit cannot match native HTML grids).

This file is the human contract. Machine-readable twins:

| Artifact | Role |
| --- | --- |
| [`react-api-contract.json`](./react-api-contract.json) | Frozen JSON (identity, images, search, availability, page BFFs) |
| `GET https://api.pokoin.com/api/__contract` | Same JSON from the live API |
| `GET https://api.pokoin.com/api/__routes` | Route index with `family` on each row |
| `GET https://api.pokoin.com/api/__routes?group=1` | Same list grouped (`page-bff`, `search`, `catalog`, …) |
| [`react-page-apis.md`](./react-page-apis.md) | Home / search / card / expansion BFF cookbook for Next.js |
| [`api-route-catalog.json`](./api-route-catalog.json) | Hosted routes from `server/api-route-manifest.js` |
| [`flutter-api-usage.json`](./flutter-api-usage.json) | 69 `/api/…` paths the Flutter client calls today |

Do **not** split `api/*.js` into subfolders. `oracle-api-server` maps
`/api/foo` → `api/foo.js`. Navigate with families in `__routes` /
`server/api-route-families.js`.

**Set desk count:** `expansion.cardCount` is
`marketplace_set_card_counts.catalog_card_count` (also on
`pokoin_pokemon_expansions.catalog_card_count`). It is the catalog grid
size, not page size 48 and not TCGDex printedTotal. Schema
`029_marketplace_set_catalog_counts.sql`.

**Silver VT:** the React pill does not search Vinted by name alone. Pokemon
query is name + collector hash (`Gumshoos 184` from `184/182`). Do not add
English set names or a `Pokemon` prefix — Vinted ANDs tokens. OP/RB keep
`One Piece Card Game` / `Riftbound TCG` plus collector. Contract `silver.vinted`,
SPA `market/src/identity.js` `vintedSearchText`. Silver CM search fallback
is the same fields: `{name token} {collector}` (`dawn 129`), not the set.

**Silver referrer:** CT/CM/VT pills `window.open` with `noopener,noreferrer`.
CT uses leftover `cardtrader.com/en/cards/{ct_id}` in the new tab (no pokoin
302). Do not cloak the click as a Google search.

Related:

- [`pokoin-api.md`](./pokoin-api.md) — Firebase auth examples
- [`marketplace-public-ids.md`](./marketplace-public-ids.md) — D00000B
- [`marketplace-card-image-pipeline.md`](./marketplace-card-image-pipeline.md) — R2 keys
- [`oracle-api-migration.md`](./oracle-api-migration.md) — handler hosting (generated from `scripts/generate-api-docs.js`)
- [`marketplace-search-ranking.md`](./marketplace-search-ranking.md) — typeahead vs catalog rank, every file, Postgres `search_weight`

Business rules live in `pokemon_card_vault/api/*.js` served by Docker
`pokoin-oracle-api` on **pokoin-marketplace**. They do **not** live in Vercel
serverless functions (Hobby cap is 12; `api/**` is excluded from web deploys).

---

## 1. Runtime topology

```text
Browser  →  pokoin.com (Vercel static / future Next.js)
              │  rewrite /api/*  and  /card-images/*
              ▼
         api.pokoin.com          cdn.pokoin.com
              │  Caddy → :18080         │  Cloudflare Worker
              ▼                         ▼
     pokoin-oracle-api            R2 cardvault-images
     (Node, Vercel-style
      handler(req,res))
              │
     ┌────────┼────────────┐
     ▼        ▼            ▼
  Postgres  Meili :7700   Firebase Admin
  (catalog) (EN search)   (bearer tokens)
```

| Piece | Where | Role |
| --- | --- | --- |
| Public site | Vercel `pokoin.com` | Static Flutter web today; React later. **Rewrites only.** |
| HTTP API | `https://api.pokoin.com` → Docker `pokoin-oracle-api:18080` on `pokoin-marketplace` (`130.61.251.250`) | All `/api/*` handlers |
| Browser path | `https://pokoin.com/api/*` | Same handlers via Vercel rewrite |
| Catalog DB | Docker `pokoin-marketplace-postgres` on the same VM | `marketplace_*`, cheapest cache, CardTrader snapshots |
| Search | Meili `127.0.0.1:7700` on marketplace VM | Indexes `marketplace_cards` (~48975 docs), `marketplace_name_tokens` |
| Images | Cloudflare Worker `cdn.pokoin.com` + R2 `cardvault-images` | Object storage. Vercel also rewrites `/card-images/*` |
| Auth | Firebase Auth | ID token is the Pokoin bearer token |
| Chat | `POST /api/pokoin-assistant` → Poko on peer1 `:8789` (VCN only) | Not a Vercel function |
| Chain | PokoinPoS on `pokoin-peer1` (`92.5.153.117`) | PKN transfers; not the marketplace API host |

**Do not** put Meili, Honcho, Ollama, or the CardVault Node API on peer1 (1 GB).
**Do not** add new Vercel serverless routes.
**Do not** treat dead Always Free peer IPs as live (`141.147.62.244`,
`92.5.23.133`, etc.). Catalog Postgres is **pokoin-marketplace**
`130.61.251.250`.
**Do not** use `deploy-oracle-api-peer3.sh` targeting that dead host.

Local API (nezopt / Pi): `npm run api:server` → `server/oracle-api-server.js`
loads the same `api/*.js` handlers. React should point `NEXT_PUBLIC_API_BASE`
at `https://api.pokoin.com` in production and at that local server in dev.

Introspection:

```text
GET /
GET /healthz
GET /api/__routes
GET /api/__contract
GET /api/marketplace-suggest?q=pika
```

`GET https://api.pokoin.com/` is the operator landing page. Product handlers
need the `/api` prefix (`/marketplace-suggest` 404s).

---

## 2. Auth contract

Firebase is the identity source of truth. There is no Pokoin session cookie
for marketplace APIs.

1. Client signs in with Firebase (same project as Flutter).
2. Client sends `Authorization: Bearer <Firebase ID token>` on protected routes.
3. `POST /api/auth-login` validates the token and returns `{ "ok": true, "auth": { "uid", "email", "emailVerified", "expiresAt" } }`.
4. Logout is client-side Firebase `signOut()`. There is no server logout.

React must use the Firebase JS SDK and attach the token on every mutating
marketplace call (cart, listings, orders, profile).

Extension bridge (keep as HTTP + HTML, not Flutter):

- `GET /extension/auth-bridge` posts `pokoin-auth-token` then closes.
- `GET /auth?from=extension&closeOnAuth=1` posts `pokoin-auth-complete`.

Common errors:

```json
{ "error": "Missing Pokoin bearer token." }
{ "error": "Firebase ID token has expired." }
```

---

## 3. Card identity (the only public id)

**Our id** `card_id` = old CardTrader blueprint × 2.

Examples: Espurr `220962`, Magcargo `587148`, Dachsbun `598052`,
Mew ex SIR Paldean Fates `548832`.

| Namespace | Formula | Appears in |
| --- | --- | --- |
| Our id | `ct_id * 2` | JSON `id` / `card_id`, paths `/marketplace/en/cards/{id}/…`, shortlinks `/{id}`, **image URL prefix** |
| `ct_id` / Milo `id` | leftover CardTrader blueprint | Postgres join, leftover **R2 object prefix**, scan gallery `hit.id`. Public URL is this × 2. **Not** a TCGplayer product id. |

Rules for React:

- Treat every path segment and `cardId` query as **our id**. Never divide by 2.
- Never multiply an id that already came from the API (that 4×s).
- `doubledCardId` / `pokoin_public_number` exist only to convert a **raw**
  leftover `ct_id` from Milo/CLIP (`hit.id`, `hit.ct_id`) into our id.
- Canonical path: `/marketplace/{lang}/cards/{card_id}/{slug}`
- Lookup: `GET /api/marketplace-card-url?cardId=220962`

SQL: `018_pokoin_card_id_ct_id.sql` (applied). Codevira **D00000B**.

Assistant card picks must use public ids. Leftover CT `274416` is Shining
Kabutops; Paldean Fates Mew ex is `548832`.

---

## 4. Images (API owns URL construction)

Public image URLs use **our id** (`card_id`). Leftover R2 object keys stay
`{ct_id}_…`. The Worker maps our id to that leftover object: try the requested
key first, then `prefix / 2` when the prefix is even. Do **not** rename the
existing catalog in R2. Do **not** tell clients to request `ct_id`.

Dachsbun: public `598052`, leftover key `299026_dachsbun-ex-….jpg`.

- `https://cdn.pokoin.com/598052_dachsbun-ex-….jpg` **200** (mapped)
- `https://cdn.pokoin.com/299026_dachsbun-ex-….jpg` **200** (legacy leftover key)

`docs/marketplace-public-ids.md` (D00000B) is the lock. Clients still **must
not invent** filenames from `card.id` + slug — use `imageUrl` / `gridImageUrl`
/ `heroImageUrl` from the API. After rewrite those strings are prefixed with
our id.

| Field | Use |
| --- | --- |
| `imageUrl` / `image_url` | Full art. Prefer this for grids if it is `.jpg`/`.png` |
| `previewImageUrl` / `preview_image_url` | Tile. API replaces fragile `/previews/*.webp` with the raster `image_url` when both exist (CanvasKit/`<img>` decode failures on tiny VP8 webp) |
| `homepageImageUrl` / `homepage_image_url` | Homepage `_homepage.webp` (VP8X). Safe to use when present |

Public clients should load:

- `https://pokoin.com` + path if the API returned a root-relative `/card-images/…`
- or the absolute `https://cdn.pokoin.com/…` URL unchanged

Worker + Vercel rewrite `/card-images/*` → CDN. Do not proxy images through
`pokoin-oracle-api`.

Observability: `GET/POST /api/marketplace-image-log`. That log is how we proved
Drowzee `241674_*.jpg` was a **decode** error, not a missing object. `prefixKind`
`public_id` is expected on served image URLs; `ct_id` means a leftover object
name.

Owner: `api/_marketplace_row.js` (`rewriteCdnPokoinPrefix`,
`preferDecodableTileImage`, `normalizeMarketplaceRow`) and Worker
`pokoin-cdn-card-images-worker.js`.

---

## 5. Search

English search uses Meili (`MARKETPLACE_SEARCH_ENGINE=meili`) on
`pokoin-marketplace` localhost `:7700`. Documents include **name**, expansion
aliases, and **`card_number`**. Numbered queries such as `Drowzee 210/198`
match in the index; the API still prefers an exact collector-number row if
Meili returns a mixed page.

Two client paths:

| Client | Endpoint | SQL |
| --- | --- | --- |
| pokoin-web header | `GET /api/marketplace-suggest?q=` | None (Meili display fields, grouped printings) |
| Flutter searchbar | `POST /api/marketplace-autocomplete` | Hydrate + rank (legacy) |
| Search results page | `GET /api/marketplace-search-page?query=` | Identity + image only (no listing-cache join) |

Query parameter: **`query`** (Flutter). Alias **`q`** is also accepted.
`?q=Cacturne` used to be ignored and returned default `search_weight` products.

| Param | Meaning |
| --- | --- |
| `query` | Name / number string |
| `limit` | Page size (search path caps ~100); suggest default 12, max 24 |
| `offset` | Meili offset |
| `search_language` / `lang` | Non-`en` stays legacy SQL |
| `productType` | Facet |
| `productSearchOnly=1` | Sealed products only |

`expansion=Scarlet & Violet` is **not** a handler param (ignored). Filter by
set after hydration or add a real facet on the API — do not assume the query
string is forwarded.

Price and stock stay on the **card page**. Typeahead is a card picker
(CardTrader-style groups), not a mini results grid.

Meili is on the marketplace VM only. Delta sync:
`scripts/meili-sync-marketplace-delta.js` (timer on that host).

Owner: `api/marketplace-search-candidates.js`
(`collectorNumberKey`, `rankRowsByQueryCollectorNumber`),
`api/marketplace-suggest.js`, `api/_meili_document.js`.

---

## 6. Availability (API owns “Out of stock”)

Flutter historically computed:

```text
isMarketAvailable = stock > 0 || hasCardTraderListing || cardtraderEligibleListingCount > 0
```

React **must not** reimplement that. Catalog rows normalized through
`normalizeMarketplaceRow` and homepage tiles from `normalizeHomeCard` include:

| Field | Type | Meaning |
| --- | --- | --- |
| `isMarketAvailable` | boolean | Show price vs “Out of stock” |
| `inStock` | boolean | Same value; HTML-friendly alias |
| `stock` / `listed_quantity` | int | Native + eligible CT quantity |
| `hasCardTraderListing` / `has_cardtrader_listing` | bool | Eligible CardTrader hub listings |
| `price` / `lowest_price_pkn` | number | PKN ask when available |

Join key for cheapest cache: `blueprint_id = ct_id` **or**
`pokoin_card_id = card_id::text`. Never `blueprint_id = public card_id`.

A card can be a real catalog row and still be unavailable if
`cheapest_homepage_cache_blueprint` has no eligible row (common on low-end
SV singles). That is data, not a CSS bug.

---

## 7. Canonical card JSON (client-agnostic)

Handlers should run `normalizeMarketplaceRow` before responding. React should
accept **both** camelCase and snake_case (Flutter already does). Preferred
camelCase for new UI:

```json
{
  "id": "548832",
  "card_id": "548832",
  "ct_id": 274416,
  "name": "Mew ex",
  "set": "Paldean Fates",
  "set_name": "Paldean Fates",
  "number": "232/091",
  "card_number": "232/091",
  "rarity": "Special Illustration Rare",
  "itemKind": "single",
  "productType": "card",
  "canonicalPath": "/marketplace/en/cards/548832/card-mew-ex-special-illustration-rare-232-091-paldean-fates",
  "imageUrl": "/card-images/274416_mew-ex-….jpg",
  "previewImageUrl": "/card-images/274416_mew-ex-….jpg",
  "homepageImageUrl": "",
  "price": 0,
  "stock": 0,
  "hasCardTraderListing": false,
  "isMarketAvailable": false,
  "inStock": false,
  "artist": "USGMEN"
}
```

`ct_id` may be present for debugging; **do not put it in the address bar**.

`GET /api/marketplace-home-page` shape:

```json
{
  "cards": [],
  "sections": {
    "recentlySeenIds": [],
    "bestSellerIds": [],
    "featuredIds": [],
    "newArrivalIds": [],
    "spotlightIds": []
  }
}
```

React should join `sections.*.Ids` to `cards` by `id`. Do not call
`GET /api/marketplace-home` from the public web renderer (Flutter snapshot,
CardTrader hydrate, often 30s+).

Detail page today: `GET /api/marketplace-card-versions?cardId={ourId}&limit=1`
returns `image_url` already on the `ct_id` prefix. Also fetch listings via
`/api/cardtrader-blueprint-listings` / live listings / marketplace listings
using **our id** (`cardId`), not a halved value.

**Page BFFs (built 2026-08-30)** — React should call these instead of
fan-out from `card_detail_screen.dart` / `home_screen.dart`:

```text
GET /api/marketplace-home-page?recentCardIds=
GET /api/marketplace-search-page?query=
GET /api/marketplace-card-page?cardId={ourId}&lang=en
GET /api/marketplace-expansion-page?expansionName=
```

`marketplace-card-page` returns card, versions, sameAs, image URLs
(`gridImageUrl` / `heroImageUrl` are full JPEGs, never `/previews/`),
offers, cheapest, artist, canonicalPath, isMarketAvailable, optional sales.
Cookbook: [`react-page-apis.md`](./react-page-apis.md).

---

## 8. Routing that React must keep as HTTP, not client guessing

| User URL | Server behavior |
| --- | --- |
| `/{digits}` | Rewrite → `GET /api/marketplace-card-shortlink?path=/{digits}` |
| `/marketplace/{digits}` | Same shortlink API |
| `/marketplace/{lang}/cards/{id}/{slug}` | Flutter/React route; bots get `/api/marketplace-card-seo` |
| `/card-images/{file}` | CDN, not Oracle API |

SEO HTML for crawlers is already an API (`marketplace-card-seo`). A Next.js
app can replace Flutter for humans and keep that SEO endpoint for bots until
SSR exists.

---

## 9. Handler map (code, not just URLs)

| Path pattern | Role |
| --- | --- |
| `api/*.js` | HTTP handlers (Vercel-style `handler(req,res)`). Hosted by `server/oracle-api-server.js` |
| `api/_*.js` | Shared libraries, **not** routes (`_marketplace_row`, `_meili_marketplace`, `_firebase`, `_client_contract`, …) |
| `server/api-route-manifest.js` | Route table for the long-running server |
| `lib/services/card_service.dart` | Flutter HTTP client — **do not port line-by-line**; call the same URLs from a JS client |
| `lib/utils/card_url.dart` | Path helpers; React should prefer `canonicalPath` from API |

There are ~174 `api/*.js` files and ~53 `_*.js` helpers. Only the manifest
routes are reachable on `api.pokoin.com`. Adding a screen means adding or
extending a handler **and** mounting it in the manifest, then regenerating
the catalog:

```bash
cd pokemon_card_vault
node -e 'const {routeDefinitions}=require("./server/api-route-manifest"); require("fs").writeFileSync("docs/api-route-catalog.json", JSON.stringify(routeDefinitions,null,2)+"\\n")'
node scripts/generate-api-docs.js
```

---

## 10. Endpoint catalog

Source: `server/api-route-manifest.js` (82 hosted routes after the React page BFFs).
Flutter currently calls 69 `/api/…` paths.

### Auth and identity

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/api/auth-login` | Bearer | `auth-login.js` | Validate the current Firebase bearer token and return safe auth metadata. |
| POST | `/api/cache-google-profile-picture` | Bearer | `cache-google-profile-picture.js` | Download the authenticated user Google avatar, optimize it, and store it in R2. |
| POST | `/api/remove-profile-picture` | Bearer | `remove-profile-picture.js` | Remove the authenticated user custom profile picture and delete old R2 object when present. |
| POST | `/api/upload-profile-picture` | Bearer | `upload-profile-picture.js` | Optimize an uploaded profile picture and store it in R2. |
| POST | `/api/wallet-auth/nonce` | Public | `wallet-auth-nonce.js` | Create a nonce challenge for wallet sign-in. |
| POST | `/api/wallet-auth/verify` | Public | `wallet-auth-verify.js` | Verify a signed wallet nonce and sign in/create the corresponding Firebase user. |

### Marketplace catalog and home

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/api/marketplace-artist-cards` | Public | `marketplace-artist-cards.js` | Return artist profile data and marketplace cards grouped by illustrator/artist attribution. |
| GET | `/api/marketplace-artist-suggestions` | Public | `marketplace-artist-suggestions.js` | Return marketplace artist suggestion rows for artist pages and admin review. |
| GET | `/api/marketplace-cards` | Public | `marketplace-cards.js` | Return searchable marketplace card and product rows. |
| GET | `/api/marketplace-competitive` | Public | `marketplace-competitive.js` | Return Limitless-backed competitive deck metagame, deck detail, tournament, standings, and pairings data for the marketplace competitive page. |
| GET | `/api/marketplace-expansions` | Public | `marketplace-expansions.js` | Return marketplace expansion list or detail snapshots. |
| GET | `/api/marketplace-home` | Public | `marketplace-home.js` | Flutter home snapshot + carousels. Optional `recentCardIds`. Slow (CardTrader hydrate). |
| GET | `/api/marketplace-home-page` | Public | `marketplace-home-page.js` | React home BFF: newest English sets + hot blueprints, no live CardTrader. |
| GET | `/api/marketplace-card-page` | Public | `marketplace-card-page.js` | React card-detail BFF (card, versions, offers, cheapest, artist). |
| GET | `/api/marketplace-search-page` | Public | `marketplace-search-page.js` | React search BFF (paged cards + product facets). Identity hydrate only. |
| GET | `/api/marketplace-expansion-page` | Public | `marketplace-expansion-page.js` | React expansion browse BFF (set metadata + singles). |
| GET | `/api/marketplace-hot-blueprints` | Public | `marketplace-hot-blueprints.js` | Return hot marketplace blueprint rows and rolling interaction counts. |

### Search and autocomplete

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/api/extension-card-search` | Public | `extension-card-search.js` | Search marketplace cards from browser-extension scraped card fields. |
| GET | `/api/marketplace-suggest` | Public | `marketplace-suggest.js` | Meili-only typeahead for pokoin-web: grouped printings, no SQL. |
| POST | `/api/marketplace-autocomplete` | Public | `marketplace-autocomplete.js` | Return ranked marketplace autocomplete/search suggestions with optional debug metadata. |
| POST | `/api/marketplace-search-candidates` | Public | `marketplace-search-candidates.js` | Return split/search candidate rows for marketplace search diagnostics and clients. |
| GET, POST | `/api/searchbar-cancel` | Public | `searchbar-cancel.js` | Mark a searchbar session as cancelled for in-process search cancellation checks. |
| GET, POST | `/api/searchbar-cards` | Public | `searchbar-cards.js` | Stable wrapper around marketplace autocomplete ranking for searchbar experiments and clients. |
| GET, POST | `/api/searchbar-token-predict` | Public | `searchbar-token-predict.js` | Return lightweight card-name token predictions for active typed fragments. |

### Card detail, URLs, SEO

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/api/cardmarket-redirect` | Public | `cardmarket-redirect.js` | Resolve a marketplace blueprint to a Cardmarket product/search URL and redirect, or return JSON when requested. |
| POST | `/api/cardmarket-scrape-observation` | Bearer | `cardmarket-scrape-observation.js` | Record Cardmarket scrape/association observations used by marketplace import review tooling. |
| GET | `/api/marketplace-blueprint-price` | Public | `marketplace-blueprint-price.js` | Return the public PKN floor price for a marketplace blueprint/card ID. |
| GET | `/api/marketplace-card-cheapest-price` | Public | `marketplace-card-cheapest-price.js` | Return the homepage-backed cheapest marketplace price for a card, including CardTrader cache availability. |
| GET | `/api/marketplace-card-sales` | Public | `marketplace-card-sales.js` | Daily sold-median series for a printing. Optional `condition` / `language` (aliases `cond` / `lang`), `reverse`, `firstEdition`, `graded`. Pi reads stored daily slices; default has no observation rows. `filters` lists keys that exist. |
| GET | `/api/marketplace-card-seo` | Public | `marketplace-card-seo.js` | Return server-rendered HTML metadata for marketplace card social previews. |
| GET, HEAD | `/api/marketplace-card-shortlink` | Public | `marketplace-card-shortlink.js` | Redirect our-id short links to canonical marketplace card URLs (our id = CardTrader ct_id * 2). |
| GET, HEAD | `/api/marketplace-card-url` | Public | `marketplace-card-url.js` | Return stored canonical_path. cardId is our marketplace id (ct_id * 2); path numbers are the same our-id. |
| GET | `/api/marketplace-card-versions` | Public | `marketplace-card-versions.js` | Return card detail/version rows for marketplace card pages. |
| GET | `/api/marketplace-cardmarket-guess-review` | Bearer | `marketplace-cardmarket-guess-review.js` | Return protected Cardmarket guess review data for search/debug operators. |

### Listings, cart, orders

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/api/marketplace-cart` | Public | `marketplace-cart.js` | Record marketplace cart add/remove analytics with optional verified user context. |
| GET, POST, PATCH | `/api/marketplace-listings` | Public | `marketplace-listings.js` | Read public active listings and create/update/decrement authenticated seller listings. |
| POST | `/api/marketplace-orders` | Bearer | `marketplace-orders.js` | Create paid marketplace orders, decrement listings, credit sellers, and send seller notifications. |
| POST | `/api/marketplace-watchlist` | Public | `marketplace-watchlist.js` | Record marketplace watchlist add/remove analytics with optional verified user context. |

### CardTrader connect and import

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/api/cardtrader-blueprint-listings` | Public | `cardtrader-blueprint-listings.js` | Return historical/daily CardTrader marketplace listing snapshots for one blueprint/card ID from Oracle. |
| POST | `/api/cardtrader-clean-listings` | Bearer | `cardtrader-clean-listings.js` | Deactivate CardTrader-linked listings owned by the authenticated seller. |
| POST, DELETE | `/api/cardtrader-connect` | Bearer | `cardtrader-connect.js` | Connect, replace, or disconnect an authenticated seller CardTrader token. |
| GET, POST | `/api/cardtrader-daily-listings-refresh` | Bearer | `cardtrader-daily-listings-refresh.js` | Manual/admin diagnostic trigger for global CardTrader marketplace listing snapshots; scheduled ingestion is owned by the Oracle/peer4 host script. |
| POST | `/api/cardtrader-disconnect` | Bearer | `cardtrader-disconnect.js` | Disconnect the authenticated seller CardTrader integration. |
| POST | `/api/cardtrader-import-dry-run` | Bearer | `cardtrader-import-dry-run.js` | Read the authenticated seller CardTrader export and return a redacted import summary without writing inventory. |
| GET | `/api/cardtrader-live-listings` | Public | `cardtrader-live-listings.js` | Return live on-demand CardTrader marketplace listings for one blueprint/card ID without persisting results. |
| GET | `/api/cardtrader-redirect` | Public | `cardtrader-redirect.js` | Public id → leftover `ct_id`, then 302 `cardtrader.com/en/cards/{ct_id}`. |
| GET | `/api/cardtrader-status` | Bearer | `cardtrader-status.js` | Return safe CardTrader integration status for the authenticated seller. |
| GET, POST | `/api/marketplace-debug-cardtrader-blueprints` | Bearer | `marketplace-debug-cardtrader-blueprints.js` | Inspect and enqueue protected CardTrader blueprint debug/import work. |

### PKN, crypto, checkout

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/api/create-pkn-checkout-session` | Bearer | `create-pkn-checkout-session.js` | Create or reconcile a Stripe Checkout session for buying PKN account balance. |
| GET, POST | `/api/crypto-pkn-purchase/:action` | Bearer | `crypto-pkn-purchase.js` | Quote, request, and check crypto-to-PKN purchase flows. |
| GET, POST | `/api/crypto-pkn-sale/:action` | Bearer | `crypto-pkn-sale.js` | Quote, request, and check PKN-to-crypto sale flows. |
| POST | `/api/earn-pkn` | Public | `earn-pkn.js` | Receive Earn PKN sharding inquiries and email the completed form to Pokoin contact. |
| POST | `/api/request-pkn-withdraw` | Bearer | `request-pkn-withdraw.js` | Withdraw PKN from site balance to a linked native PKN address. |
| POST | `/api/stripe-webhook` | Public | `stripe-webhook.js` | Handle Stripe Checkout webhooks and credit completed PKN purchases. |
| GET, POST | `/api/wpkn-exchange/:action` | Bearer | `wpkn-exchange.js` | Quote, request, and check native PKN/wPKN exchange flows. |

### Forum and social

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/api/forum` | Public | `forum.js` | Read forum categories, topic lists, or a single topic with posts. |
| POST | `/api/forum-create-post` | Bearer | `forum-create-post.js` | Create an authenticated forum reply. |
| POST | `/api/forum-create-topic` | Bearer | `forum-create-topic.js` | Create an authenticated forum topic. |
| POST | `/api/forum-upload-media` | Bearer | `forum-upload-media.js` | Optimize forum image media and store it in R2. |
| POST | `/api/social-autopost` | Bearer | `social-autopost.js` | Post supplied Pokoin social copy or card payloads to configured Telegram and X channels, optionally using the dedicated peer2 social copy agent. |
| GET, POST | `/api/social-autopost/hot-card` | Bearer | `social-autopost-hot-card.js` | Select a hot Pokoin marketplace card and post it to configured social channels, optionally using the dedicated peer2 social copy agent. |
| POST | `/api/social-post-agent` | Bearer | `social-post-agent.js` | Generate Telegram and X copy through the dedicated peer2 social agent without posting to providers. |

### Assistant / Pokontact

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/api/pokoin-assistant` | Public | `pokoin-assistant.js` | Answer Pokontact assistant chat requests with marketplace grounding and optional service handoff. |

### Scan / training

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET, POST | `/api/flutter-debug-logs` | Bearer | `flutter-debug-logs.js` | Record and read protected Flutter client debug logs. |
| POST | `/api/trainingai-card-classify` | Public | `trainingai-card-classify.js` | Proxy card image classification requests to the Pokoin TrainingAI Oracle classifier or Hugging Face Space fallback. |

### Ops and debug

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/api/limitless-expansion-blueprints` | Public | `limitless-expansion-blueprints.js` | Return Limitless expansion-to-Pokoin blueprint mapping rows. |
| GET, POST | `/api/marketplace-debug-artists` | Bearer | `marketplace-debug-artists.js` | Inspect and update marketplace artist enrichment/debug classification data. |
| GET | `/api/marketplace-debug-events` | Bearer | `marketplace-debug-events.js` | Return marketplace event analytics debug data. |
| GET, POST | `/api/marketplace-debug-refinement` | Bearer | `marketplace-debug-refinement.js` | Inspect and update marketplace search refinement/debug data. |
| GET, POST | `/api/marketplace-image-log` | Public | `marketplace-image-log.js` | Ring-buffer exact marketplace image URLs served or failed during navigation. |

### Other

| Method | Path | Auth | Handler | Purpose |
| --- | --- | --- | --- | --- |
| GET, POST | `/api/deck-card-version-lookup` | Public | `deck-card-version-lookup.js` | Return ranked marketplace card versions for structured decklist card fields. |
| POST | `/api/marketplace-event` | Public | `marketplace-event.js` | Record public marketplace interaction/search events and refresh hot-card aggregates opportunistically. |
| GET, POST | `/api/marketplace-expansion-symbols` | Bearer | `marketplace-expansion-symbols.js` | Read or update marketplace expansion symbol metadata. |
| POST | `/api/register-email` | Public | `register-email.js` | Start email/password signup by storing pending signup data and sending verification mail. |
| GET, POST | `/api/search-recipient-emails` | Bearer | `search-recipient-emails.js` | Search usernames for transfers, ensure a username, or update the authenticated user username. |
| POST | `/api/signup-notification` | Bearer | `signup-notification.js` | Send signup notification email for the authenticated user once. |
| POST | `/api/top-up-account-balance` | Bearer | `top-up-account-balance.js` | Verify a native PKN funding transaction and credit authenticated site balance. |
| POST | `/api/transfer-account-balance` | Bearer | `transfer-account-balance.js` | Transfer PKN site balance from the authenticated user to another Pokoin account. |
| POST | `/api/unlock-silver` | Bearer | `unlock-silver.js` | Unlock Silver status/features for the authenticated account. |
| GET, POST | `/api/user-current-page` | Public | `user-current-page.js` | Store or read the current internal Pokoin page for an assistant browser session. |
| POST | `/api/verify-email-signup` | Public | `verify-email-signup.js` | Verify a pending email signup token, create/claim the Firebase user, and send welcome/notification emails. |
| POST | `/api/wallet-link` | Bearer | `wallet-link.js` | Link a wallet to the authenticated Firebase account. |
| POST | `/api/wallet-link/complete` | Public | `wallet-link-complete.js` | Complete a wallet-link session from a signed wallet payload. |
| POST | `/api/wallet-link/session` | Bearer | `wallet-link-session.js` | Create a wallet-link session for an authenticated Firebase account. |


### Path aliases used by Flutter but expressed as `:action` in the manifest

- `/api/crypto-pkn-purchase/quote`
- `/api/crypto-pkn-purchase/request`
- `/api/crypto-pkn-sale/quote`
- `/api/crypto-pkn-sale/request`
- `/api/ensure-username`
- `/api/wpkn-exchange/quote`
- `/api/wpkn-exchange/request`
- `/api/wpkn-exchange/status`
- `/api/wpkn-pkn-quote`

Manifest-only (SEO, webhooks, extension, social, live CardTrader — still
required for React/ops):

- `/api/auth-login`
- `/api/cardmarket-scrape-observation`
- `/api/cardtrader-blueprint-listings`
- `/api/cardtrader-daily-listings-refresh`
- `/api/cardtrader-live-listings`
- `/api/cardtrader-redirect`
- `/api/crypto-pkn-purchase/:action`
- `/api/crypto-pkn-sale/:action`
- `/api/extension-card-search`
- `/api/limitless-expansion-blueprints`
- `/api/marketplace-card-seo`
- `/api/marketplace-card-shortlink`
- `/api/searchbar-cards`
- `/api/social-autopost`
- `/api/social-autopost/hot-card`
- `/api/social-post-agent`
- `/api/stripe-webhook`
- `/api/trainingai-card-classify`
- `/api/wpkn-exchange/:action`

---

## 11. Logic that must stay on the server (React forbidden)

The current Flutter web client still duplicates some of this. The React
cutover is the chance to **delete** it from the browser.

| Rule | Server owner | Do not do in React |
| --- | --- | --- |
| Public id ×2 / ÷2 | API + `018` SQL | Halve path ids; double catalog ids |
| CDN filename prefix | `rewriteCdnPokoinPrefix` / Worker leftover map | Concatenate `card.id + "_" + slug` |
| Preview webp vs jpg | `preferDecodableTileImage` | Prefer `/previews/*.webp` because it is smaller |
| In-stock banner | `isMarketAvailable` on the JSON | Recompute from partial fields |
| Search ranking | Meili (`card_number` indexed); suggest is Meili-only | ILIKE in the browser |
| Cheapest PKN | `cheapest_homepage_cache_blueprint` join on **ct_id** | Join listings on public id |
| Canonical slug | `marketplace_card_urls.canonical_path` | Guess slugs from rarity+name |
| Assistant card picks | `pokoin-assistant` curated **public** ids | Hardcode old CardTrader ids |
| Payments | Stripe webhook + Oracle handlers | Trust client-calculated PKN |

If React needs a new screen, add or extend an `api/*.js` handler and mount it
in `server/api-route-manifest.js`. Do not hide business rules in Next.js
`getServerSideProps` copies of SQL.

---

## 12. Flutter-only composition to replace with APIs

These are still assembled in `lib/` today. They should become HTTP so React
does not copy 7k-line screens.

| Client behavior today | Target API |
| --- | --- |
| Spotlight ranking by local recent views | `GET /api/marketplace-home?recentCardIds=` returns `sections.spotlightIds` |
| Client filters (set, rarity, price, in-stock) | `GET /api/marketplace-search-page` / `marketplace-cards`; do not filter a home dump as the catalog |
| `PokemonCard.isMarketAvailable` getter | **Done on API** (`isMarketAvailable` / `inStock`) |
| `rewriteCdnPrefixToOurId` | **Done on API** image fields; React uses `gridImageUrl` / `heroImageUrl` |
| Detail hydration from versions + listings + cheapest + artist | **Done:** `GET /api/marketplace-card-page?cardId=` |
| Expansion browse (`getCardsByExpansion`) | **Done:** `GET /api/marketplace-expansion-page?expansionName=` |
| Cart badge / watchlist counts | Existing cart/watchlist APIs; React should not keep a parallel IndexedDB catalog |
| GoRouter path parsing | Next.js app router using the same `canonicalPath` |

---

## 13. React migration sequence (strangler)

1. **Contract freeze** — this file + `GET /api/__contract` + `docs/react-page-apis.md`.
2. **Next.js app** on Vercel, rewrite `/api/*` to `api.pokoin.com` (already
   the production pattern). No serverless handlers.
3. **Home** — `GET /api/marketplace-home-page` + `<img src={card.gridImageUrl}>`.
4. **Search** — `GET /api/marketplace-suggest?q=` (header) + `GET /api/marketplace-search-page?query=`.
5. **Detail** — `GET /api/marketplace-card-page?cardId=` (do not fan-out).
6. **Expansion** — `GET /api/marketplace-expansion-page?expansionName=`.
7. Keep Flutter **iOS/Android** on the same APIs.
8. Turn off Flutter web when React matches home/search/detail/expansion.

Flutter web is laggy because CanvasKit + `WebHtmlElementStrategy.prefer` +
Hero-off + 180px previews stretched to card frames. Do not spend more time
patching that renderer; paint full JPEGs in React instead.

Do not strangler-replace wallet, Stripe, or PKN purchase until those APIs are
called bit-for-bit from React with the same bearer token.

Suggested Next.js env:

```text
NEXT_PUBLIC_API_BASE=https://api.pokoin.com
NEXT_PUBLIC_SITE_ORIGIN=https://pokoin.com
NEXT_PUBLIC_FIREBASE_*   # same project as Flutter
```

Fetch helper (sketch):

```js
export async function pokoinFetch(path, { token, ...init } = {}) {
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  const res = await fetch(`${process.env.NEXT_PUBLIC_API_BASE}${path}`, {
    ...init,
    headers,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  return res.json();
}
```

---

## 14. Local / live verification

```bash
cd pokemon_card_vault
node --test api/_marketplace_row.test.js api/marketplace-cards.test.js
node scripts/check-oracle-api-server.js

curl -sS https://api.pokoin.com/api/__contract | python3 -m json.tool | head
curl -sS https://api.pokoin.com/api/__routes | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["routes"]))'
curl -sS --max-time 8 'https://api.pokoin.com/api/marketplace-home-page' | python3 -c 'import sys,json; d=json.load(sys.stdin); c=d["cards"][0]; print(c.get("name"), c.get("isMarketAvailable"), c.get("gridImageUrl","")[:80])'
curl -sS 'https://api.pokoin.com/api/marketplace-cards?query=Drowzee%20210/198&limit=3'
curl -sS 'https://api.pokoin.com/api/marketplace-card-url?cardId=548832'
```

Image sanity: HEAD the **`imageUrl` the API returned**, not a public-id prefix.

---

## 15. Critical areas (same bar as payments)

Stripe, user balance, PKN/wallet, authentication, DB migrations, blockchain,
and marketplace purchase flow stay on this API. React is a renderer. Never
assume from this document alone for those paths — read the handler, keep
diffs small, explain risk first.

Last updated: 2026-09-05. Identity: leftover `ct_id` / Milo `hit.id`; public
`card_id` = that × 2. Contract `2026-09-05.6`.
