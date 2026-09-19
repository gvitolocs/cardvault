# React page APIs (strangler contract)

These page BFFs are what a Next.js/React public site should call
for home, search, card detail, and expansion browse. Home for React is
`GET /api/marketplace-home-page` (not the Flutter `marketplace-home`
snapshot). They live on `https://api.pokoin.com` (also rewritten at
`https://pokoin.com/api/*`).
Do **not** reimplement them in `getServerSideProps`. Do **not** add Vercel
serverless functions.

Live machine contract: `GET https://api.pokoin.com/api/__contract`
Human contract: `docs/react-api-architecture.md`

Flutter Android/iOS keeps using the older granular APIs
(`marketplace-card-versions`, `marketplace-listings`, `marketplace-cards`).
The page BFFs compose those handlers.

## Identity

Every `cardId` is the **public** Pokoin id (`ct_id * 2`). Examples:

| Card | Public id | `ct_id` (leftover R2 prefix) |
| --- | --- | --- |
| Espurr | `220962` | `110481` |
| Magcargo | `587148` | `293574` |
| Mew ex SIR Paldean Fates | `548832` | `274416` |
| Mega Lucario ex | `703382` | `351691` |

Never divide. Never invent CDN filenames. Use `imageUrl` /
`gridImageUrl` / `heroImageUrl` from the JSON (those prefixes are our id).
The Worker maps `{card_id}_` to leftover `{ct_id}_` objects.

## Images (why Flutter web looked like stretched previews)

| Field | Meaning | React must |
| --- | --- | --- |
| `imageUrl` | Full art, typically 330×460 baseline JPEG | OK |
| `previewImageUrl` | 180×251, often progressive JPEG under `/previews/` | **Do not** use as hero or grid |
| `homepageImageUrl` | Real only when it contains `_homepage.webp`. New Mega cards currently copy the preview URL here | Ignore unless `_homepage.webp` |
| `gridImageUrl` | Full raster, never `/previews/` | **Use in grids** |
| `heroImageUrl` | Full raster | **Use in detail / CSS hero** |
| `tileImageUrl` | `_homepage.webp` if present, else full raster | Compact carousels |

Flutter web skipped Hero and preferred homepage/preview because CanvasKit
cannot decode progressive JPEG. React uses native `<img>` / Next `Image`,
so it should always paint the full JPEG.

## 1. Home

```http
GET /api/marketplace-home-page
GET /api/marketplace-home-page?recentCardIds=703382,587148
```

React must call **`marketplace-home-page`**. `GET /api/marketplace-home` is
the Flutter snapshot (CardTrader hydrate, often 30s+). Do not use it from
the public web renderer.

The page BFF uses indexed SQL only: newest Mega Evolution / Phantasmal Flames /
Black Bolt singles, plus `marketplace_hot_blueprints` joined on `ct_id`.
No live CardTrader. No `ORDER BY imported_at` on the full catalog.

Response:

```json
{
  "cards": [{ "id": "703382", "name": "Mega Lucario ex", "gridImageUrl": "/card-images/703382_….jpg" }],
  "sections": {
    "newArrivalIds": ["703382"],
    "featuredIds": [],
    "bestSellerIds": [],
    "recentlySeenIds": ["703382"],
    "spotlightIds": ["703382"]
  }
}
```

Join `sections.*.Ids` to `cards` by `id`. `recentCardIds` is not cached
(`Cache-Control: private, no-store`). Without it, home is cached ~30s.

`newArrivalIds` is newest English singles with collector numbers
(`028/132`), not products.

## 1b. Portfolio / Explore

```http
GET /api/marketplace-portfolio
GET /api/marketplace-portfolio?id=806602
GET /api/marketplace-portfolio?game=riftbound
```

Pokoin catalog (`marketplace_search_candidates`) with native listing PKN
overlaid when `marketplace_user_listings` exists. Pokemon also overlays
`cheapest_homepage_cache_blueprint` (already PKN). `?id=` matches public
`card_id` **or leftover `ct_id`** (Yasuo `806602` / `403301`). Images are
`cdn.pokoin.com` / `/card-images/…` — never CardTrader leftover blueprint
URLs. Never USD. Unpriced rows return `pricePkn: 0`. Empty id miss returns
empty `items`. Satellite default `limit` 2000 (max 2500). Pokemon 400/500.

## 2. Search

```http
GET /api/marketplace-search-page?query=Charizard&limit=100&offset=0
GET /api/marketplace-search-page?q=Drowzee%20210/198
GET /api/marketplace-suggest?q=char&limit=12
POST /api/marketplace-autocomplete   (Flutter searchbar only)
```

Response:

```json
{
  "query": "Charizard",
  "limit": 100,
  "offset": 0,
  "count": 100,
  "hasMore": true,
  "cards": [],
  "facets": { "products": [{ "productType": "card", "count": 80 }] }
}
```

English `query` uses Meili on the marketplace VM. Alias `q` works.
The search **page** hydrates identity and image only (no listing-cache join).
Header typeahead is `GET /api/marketplace-suggest` (Meili-only grouped
printings). Group order for plain prefixes is **base name first**
(`mimik` → Mimikyu, not Mimikyu GX). Catalog `search_weight` still boosts
GX/products in Meili; the popup reranks in `api/_meili_suggest.js`. Full
map: [`marketplace-search-ranking.md`](./marketplace-search-ranking.md).
Load more with `offset += limit` while `hasMore`.

Expansion browse is **not** `?expansion=Mega+Evolution` on search.
That param is ignored. Use the expansion page API.

## 3. Card detail

```http
GET /api/marketplace-card-page?cardId=703382&lang=en
GET /api/marketplace-card-page?cardId=548832&includeSales=1
GET /api/marketplace-card-page?cardId=703382&includeSameAs=1&liveOffers=1
```

First paint is a `card_id` primary-key lookup plus native listings. Same-set
printings come from `set_name` + `name` (not `marketplace-card-versions`).
`includeSameAs` and `liveOffers` are **off** unless the client asks; both
were the 30s hang (statement timeout on sameAs, live CardTrader via
`readPublicOffersForCard`).

`GET /api/marketplace-listings?cardId=&nativeOnly=1` skips live CardTrader
for the same reason. Flutter card detail still uses the default live merge.

Response keys: `card`, `version` (CLIP `pokoin_version_sets` key, also
`card.version`), `versionCount`, `versions` (same-artwork printings),
`sameAs`, `offers`, `cheapest`, `sales` (empty unless `includeSales=1`),
`artist`, `canonicalPath`, `seo`.

`card.heroImageUrl` is the full JPEG. Offers are native listings plus
live CardTrader (pknreserve). `sameAs` is other printings of the same
name/set.

Canonical browser path is `card.canonicalPath`, also available from
`GET /api/marketplace-card-url?cardId=703382`. Shortlinks `/{digits}`
still go through `marketplace-card-shortlink`.

## 4. Expansion browse

```http
GET /api/marketplace-expansion-page?expansionName=Mega%20Evolution&productType=card
GET /api/marketplace-expansion-page?slug=mega-evolution
GET /api/marketplace-expansion-page
```

The last form returns `{ expansions: [...] }` for the nav. The named
form returns `{ expansion, cards, total, count, hasMore }`.
`expansion.cardCount` / `total` is the **stored catalog size**
(`marketplace_set_card_counts.catalog_card_count`, copied onto
`pokoin_pokemon_expansions.catalog_card_count`). That is how many singles
with art the set grid will show, not the first page (48) and not TCGDex
`set_official_card_count`. Refresh:
`SELECT public.refresh_marketplace_set_catalog_counts();` (also hooked from
`refresh_marketplace_oracle_projections`). Do not `COUNT(*)` on the request.

Mega Evolution singles live here. Mega Lopunny ex is **Phantasmal
Flames**, not Mega Evolution.

## 5. Auth / cart / checkout (keep existing APIs)

React must not invent a second wallet. Same Firebase project, same
bearer token.

| Need | API |
| --- | --- |
| Login probe | `POST /api/auth-login` |
| Cart analytics | `POST /api/marketplace-cart` |
| Watchlist | `/api/marketplace-watchlist` |
| Create listing | `POST /api/marketplace-listings` (bearer) |
| Buy PKN | `POST /api/create-pkn-checkout-session` |
| Assistant | `POST /api/pokoin-assistant` |

## 6. Local tests

```bash
cd pokemon_card_vault
npm run api:server
# NEXT_PUBLIC_API_BASE=http://127.0.0.1:8080
node --test api/marketplace-card-page.test.js \
  api/marketplace-home-page.test.js \
  api/marketplace-search-page.test.js \
  api/marketplace-expansion-page.test.js \
  api/marketplace-portfolio.test.js \
  api/_marketplace_react_card.test.js \
  api/_marketplace_home_recent.test.js
```

Local tests do **not** hit Postgres. They mock the composed handlers.

## 7. Verify live

```bash
curl -sS https://api.pokoin.com/api/__contract | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], list(d["pageApis"]))'
curl -sS --max-time 8 'https://api.pokoin.com/api/marketplace-home-page' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["cards"]), d["sections"])'
curl -sS --max-time 8 'https://api.pokoin.com/api/marketplace-card-page?cardId=703382' | python3 -c 'import json,sys; d=json.load(sys.stdin); c=d["card"]; print(c["name"], c["heroImageUrl"], c["isMarketAvailable"])'
curl -sS --max-time 15 'https://api.pokoin.com/api/marketplace-search-page?query=Mega%20Lopunny%20ex&limit=5&includeFacets=0'
curl -sS --max-time 8 'https://api.pokoin.com/api/marketplace-suggest?q=pika&limit=8'
curl -sS --max-time 15 'https://api.pokoin.com/api/marketplace-expansion-page?expansionName=Mega%20Evolution&limit=5'
```
