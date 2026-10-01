'use strict';

const { routeDefinitions } = require('../server/api-route-manifest');
const { FAMILIES, familyForPath } = require('../server/api-route-families');

/**
 * Client reference aligned with the public 2026-10-01 contract.
 * Route inventory must describe this release, never a copied live-server list.
 * Served at GET /api/__contract; regenerate docs with npm run api:docs.
 */
const CLIENT_REFERENCE = {
  "version": "2026-10-01.1",
  "title": "Pokoin marketplace client contract for React / Flutter / JS",
  "hosts": {
    "api": "https://api.pokoin.com",
    "publicSite": "https://pokoin.com",
    "cdn": "https://cdn.pokoin.com",
    "rewriteNote": "https://pokoin.com/api/* rewrites to https://api.pokoin.com/api/*. Do not add Vercel serverless functions.",
    "localDev": "npm run api:server; default http://127.0.0.1:8080 (PORT or ORACLE_API_PORT overrides)",
    "apiRuntime": "Docker pokoin-oracle-api on pi-home (Raspberry Pi), exposed through Cloudflare tunnel"
  },
  "identity": {
    "publicIdField": [
      "id",
      "card_id"
    ],
    "formula": "For CardTrader-backed catalog records: public_card_id = cardtrader_blueprint_id * 2. Use the returned public id; do not apply this formula to arbitrary external/provider ids.",
    "examples": {
      "espurr": {
        "card_id": "220962",
        "ct_id": 110481
      },
      "magcargo": {
        "card_id": "587148",
        "ct_id": 293574
      },
      "dachsbun": {
        "card_id": "598052",
        "ct_id": 299026
      },
      "mewExSirPaldeanFates": {
        "card_id": "548832",
        "ct_id": 274416
      },
      "megaLucarioEx": {
        "card_id": "703382",
        "ct_id": 351691
      }
    },
    "rules": [
      "Path segments and cardId query params are always the public id.",
      "Never divide a public id by 2 when calling the API.",
      "Never multiply an id that already came from the API (that 4xs).",
      "doubledCardId is only for raw leftover ct_id from Milo/CLIP (hit.id, hit.ct_id, blueprint_id).",
      "Milo gallery identity is leftover ct_id (manifest identity=ct_id). Public card_id = ct_id * 2. TCGplayer product ids are not Milo ids.",
      "ct_id may appear on JSON for joins/debug; never put it in the address bar."
    ],
    "canonicalPath": "/marketplace/{lang}/cards/{card_id}/{slug}",
    "lookup": "GET /api/marketplace-card-url?cardId={publicId}",
    "sql": "018_pokoin_card_id_ct_id.sql",
    "decision": "Codevira D00000B"
  },
  "images": {
    "r2KeyPrefix": "Legacy Pokemon objects use ct_id; satellite games may use game-specific prefixes. Treat keys as opaque and use API image URLs.",
    "doNotBuildFilenamesFromPublicId": true,
    "fields": {
      "imageUrl": "Full art (typically 330x460 baseline JPEG). Prefer this for grids and heroes.",
      "previewImageUrl": "180px tile. Do not stretch as a hero. API may still return /previews/*.jpg.",
      "homepageImageUrl": "Only use when it contains _homepage.webp. Often wrongly equals preview for new cards.",
      "gridImageUrl": "React grid: always the full raster, never /previews/.",
      "heroImageUrl": "React detail/hero: always the full raster.",
      "tileImageUrl": "React compact tile: _homepage.webp when present, else full raster. Never preview JPEG."
    },
    "cdnWorker": "pokoin-cdn-card-images",
    "r2Bucket": "cardvault-images",
    "observability": "GET/POST /api/marketplace-image-log",
    "decodeNote": "Flutter CanvasKit fails progressive JPEG and tiny VP8 preview webp. React <img> can decode those, but still must not use 180px previews as full-size art.",
    "rules": [
      "Use gridImageUrl for grids and heroImageUrl for detail.",
      "Do not synthesize image keys from public IDs. Palworld/Cyberpunk legacy image keys use raw CardTrader IDs; the API handles this mapping."
    ]
  },
  "availability": {
    "serverOwnsFlag": true,
    "fields": {
      "isMarketAvailable": "boolean — show price vs Out of stock",
      "inStock": "boolean — same value, HTML-friendly alias",
      "stock": "int — native + eligible CardTrader quantity",
      "hasCardTraderListing": "bool",
      "cardtraderEligibleListingCount": "int",
      "price": "number PKN ask when available"
    },
    "formula": "stock > 0 || hasCardTraderListing || cardtraderEligibleListingCount > 0",
    "cheapestCacheJoin": "blueprint_id = ct_id OR pokoin_card_id = card_id::text. Never blueprint_id = public card_id.",
    "emptyCacheIsData": "SV commons can be genuine OOS if cheapest_homepage_cache_blueprint has no row."
  },
  "search": {
    "engine": "meili",
    "scope": "Meilisearch for English Pokemon retrieval; SQL for satellite games and legacy non-English full search",
    "host": "127.0.0.1:7700 on pi-home alongside the public API",
    "indexes": [
      "marketplace_cards",
      "marketplace_name_tokens"
    ],
    "queryParam": "query",
    "queryAlias": "q",
    "notes": [
      "Pokemon suggest retrieves grouped printings from Meilisearch; optional SQL enrichment supplies title language and expansion nationality.",
      "Satellite-game suggest uses the selected game catalog SQL path.",
      "Non-English Pokemon suggest returns an empty result with meta.reason=meili_unavailable when the language gate is closed; do not assume it uses full-search SQL fallback.",
      "Search page hydrates identity/image and overlays cached cheapest PKN. Shop listing rows remain on the card page.",
      "POST /api/marketplace-autocomplete remains the Flutter pool endpoint; POST /api/searchbar-token-predict supplies ghost-text prediction.",
      "Plain prefixes favor the base display name; explicit variant tokens retain variant intent.",
      "Meilisearch stays on pi-home. Oracle is the catalog import/write primary."
    ],
    "params": {
      "query": "Name / number string",
      "limit": "Page size (search path caps ~100)",
      "offset": "Meili offset",
      "search_language": "Display/search language; aliases lang and language. Default en.",
      "productType": "Facet",
      "productSearchOnly": "1 = Product search universe: sealed products plus the jumbo subtype (no separate jumbo tab)",
      "game": "Game scope; see games.supported",
      "print_language": "Print universe all|western|japanese|korean|chinese; alias printLanguage. Japanese and Korean selections share the JP/KO universe.",
      "match": "Suggest only: all requires every query token; omitted uses the default matching strategy."
    },
    "autocomplete": "POST /api/marketplace-autocomplete { search_term, result_limit } (Flutter)",
    "suggest": "GET /api/marketplace-suggest?q= (pokoin-web popup)",
    "fullSearch": "GET /api/marketplace-cards?query=",
    "searchPage": "GET /api/marketplace-search-page?query=",
    "tokenPredict": "POST /api/searchbar-token-predict",
    "counts": {
      "suggest": "shown is the capped number of popup printings (at most 20). count is the matching/filtered universe estimate, not the popup length. globalCount is available on Pokemon responses.",
      "searchPage": "count is the returned page length. total is the matching query total when available, otherwise null; never treat count as the catalog total. Use hasMore and offset for pagination."
    }
  },
  "auth": {
    "provider": "Firebase Auth",
    "header": "Authorization: Bearer <Firebase ID token>",
    "login": "POST /api/auth-login",
    "logout": "Client-side Firebase signOut. No server logout.",
    "extensionBridge": "GET /extension/auth-bridge",
    "rules": [
      "Protected routes derive UID from the verified Firebase token, never from a client body UID.",
      "Do not log or embed bearer tokens in documentation. See routes[].auth for each endpoint."
    ]
  },
  "pageApis": {
    "home": {
      "path": "GET /api/marketplace-home-page",
      "legacy": "GET /api/marketplace-home is the Flutter snapshot (CardTrader hydrate, often 30s+). React must not call it.",
      "query": "game; recentCardIds optional comma-separated public ids; limit default 36, max 48",
      "returns": "game, cards[], sections.{recentlySeenIds,bestSellerIds,featuredIds,newArrivalIds,spotlightIds}; optional source",
      "cache": "With recentCardIds: private, no-store. Otherwise public max-age=15, s-maxage=30, stale-while-revalidate=60."
    },
    "suggest": {
      "path": "GET /api/marketplace-suggest",
      "query": "q|query, game, limit (default 20, max 24 groups; popup capped at 20 printings), search_language|lang|language, print_language|printLanguage, match=all optional",
      "returns": "query, game, groups[] of {name, printings[{id,set,number,rarity,image,href,...}]}, shown, count; Pokemon also globalCount and printLanguage. Empty/degraded responses can include meta.reason.",
      "cache": "public max-age=5, s-maxage=30, stale-while-revalidate=120 on successful reads; degraded responses use shorter caching."
    },
    "search": {
      "path": "GET /api/marketplace-search-page",
      "query": "query|q, game, limit (default/max 100), offset (default 0), productType, productSearchOnly=1, search_language|lang|language, print_language|printLanguage, includeFacets (default enabled; 0 disables)",
      "returns": "query, game, productType, productSearchOnly, lang, cards[], facets.products[], count, total (nullable), hasMore, limit, offset. Identity/image hydrate plus cached cheapest PKN; no live shop-listing read.",
      "cache": "public max-age=15, s-maxage=60, stale-while-revalidate=120"
    },
    "card": {
      "path": "GET /api/marketplace-card-page",
      "query": "cardId|id required (public id), game, lang|language|search_language, cardSlug|slug, includeSales, includeOffers, includeSameAs, liveOffers (all flags default off; 1|true|yes enables), offerLimit (default 40, max 80), salesLimit (default 40, max 120)",
      "returns": "card, game, version, visualTheme, versionCount, versions[], rarities[], neighbors.{prev,next}, sameAs[], offers[], cheapest, sales[], artist, canonicalPath, seo, lookup",
      "offers": "includeOffers=1 is required to populate offers. liveOffers=1 additionally requests live CardTrader; otherwise only native listings are requested. Optional reads may return empty arrays on timeout/failure.",
      "cache": "public max-age=10, s-maxage=30, stale-while-revalidate=60"
    },
    "expansion": {
      "path": "GET /api/marketplace-expansion-page",
      "query": "game; expansionName or slug; productType default card; limit (default 200, max 400), offset. Omit both name and slug for the expansion index (limit default 500, max 2000).",
      "returns": "expansion { name, slug, cardCount }, cards[], total, count, hasMore, limit, offset. cardCount/total is stored catalog_card_count (grid singles with art), not the page size and not TCGDex printedTotal.",
      "cardCount": "Read public.marketplace_set_card_counts.catalog_card_count / pokoin_pokemon_expansions.catalog_card_count. Refresh: refresh_marketplace_set_catalog_counts(). Do not COUNT(*) on the request."
    },
    "portfolio": {
      "path": "GET /api/marketplace-portfolio",
      "query": "game; id optional; limit Pokemon default 400/max 500, satellite default 2000/max 2500",
      "returns": "game, currency, totals, games[], items[], holdings[]. Catalog explore data, not authenticated personal holdings.",
      "pricing": "PKN, with available native-listing and Pokemon cheapest-cache overlays; unpriced rows use pricePkn=0."
    }
  },
  "silver": {
    "cardtrader": "SPA opens leftover https://www.cardtrader.com/en/cards/{ct_id} with window.open noopener,noreferrer (no Pokoin referrer, not a Google cloak). Lookup fallback GET /api/cardtrader-redirect?id={publicId}&format=json. Sanji 818358 → 409179. Never send public ids to cardtrader.com.",
    "cardmarket": "GET /api/cardmarket-redirect?id={publicId}&format=json. Pokemon: stored/product URL, else Singles search {name token} {collector} (dawn 129), not set name. OP: /en/OnePiece/Products/Search {name} {number}. RB: /en/Riftbound/Products/Search. Datacenter IPs often get Cloudflare 403 on cardmarket.com — the user browser opens the URL.",
    "vinted": "SPA builds https://www.vinted.it/catalog?search_text=. Pokemon: {name} {collector hash} (Gumshoos 184 from 184/182), not name alone and not English set name (Vinted ANDs tokens). OP: One Piece Card Game {name} {number}. RB: Riftbound TCG {name} {number}."
  },
  "canonicalCardJson": {
    "id": "548832",
    "card_id": "548832",
    "ct_id": 274416,
    "name": "Mew ex",
    "set": "Paldean Fates",
    "number": "232/091",
    "rarity": "Special Illustration Rare",
    "itemKind": "single",
    "productType": "card",
    "canonicalPath": "/marketplace/en/cards/548832/card-mew-ex-special-illustration-rare-232-091-paldean-fates",
    "imageUrl": "/card-images/{card_id}_….jpg",
    "previewImageUrl": "/card-images/{card_id}_….jpg",
    "gridImageUrl": "/card-images/{card_id}_….jpg",
    "heroImageUrl": "/card-images/{card_id}_….jpg",
    "isMarketAvailable": false,
    "inStock": false,
    "acceptBothCamelAndSnake": true
  },
  "forbiddenInReact": [
    "Halve path ids or double catalog ids",
    "Concatenate card.id + '_' + slug for CDN keys",
    "Prefer /previews/*.webp or /previews/*.jpg because they are smaller",
    "Use homepageImageUrl when it is a /previews/ URL",
    "Recompute isMarketAvailable from partial fields",
    "ILIKE search in the browser",
    "Join listings on public id instead of ct_id",
    "Guess slugs instead of canonicalPath",
    "Hardcode leftover CardTrader ids (Mew 274416 is Shining Kabutops)",
    "Trust client-calculated PKN for payments",
    "Add Vercel serverless marketplace handlers",
    "Send public card_id to cardtrader.com (use leftover ct_id via cardtrader-redirect)"
  ],
  "navigation": {
    "contract": "GET /api/__contract",
    "routes": "GET /api/__routes",
    "routesGrouped": "GET /api/__routes?group=1",
    "routesByFamily": "GET /api/__routes?family=page-bff",
    "families": [
      "page-bff",
      "search",
      "card",
      "catalog",
      "commerce",
      "scan",
      "cardtrader",
      "cardmarket",
      "auth",
      "payments",
      "assistant",
      "social",
      "debug",
      "other"
    ],
    "doNotMoveApiFiles": true,
    "docs": [
      "docs/react-api-architecture.md",
      "docs/react-page-apis.md",
      "docs/oracle-api-migration.md",
      "docs/api-route-catalog.json",
      "docs/pokoin-api.md",
      "workflows/meilisearch-peer-workflow.md",
      "memory/architecture.md"
    ]
  },
  "bffGaps": [],
  "stranglerOrder": [
    "home",
    "search",
    "card-detail",
    "expansion"
  ],
  "flutterNativeStays": true,
  "doNotRewriteWholeFlutterRepo": true,
  "updatedAt": "2026-10-01",
  "scope": "Client API reference. Publication of this contract does not deploy business-logic changes. routes and routeCount are derived from the running server manifest.",
  "topology": {
    "api": "pi-home",
    "meilisearch": "pi-home, http://127.0.0.1:7700",
    "cache": "Valkey on pi-home",
    "pokemonCatalogReads": "Postgres streaming replica on pi-home",
    "catalogPrimary": "pokoin-marketplace Oracle: CardTrader imports and migrations write to the primary, never to the Pi replica",
    "satelliteCatalogs": "Game-scoped isolated databases; selecting a game does not create an isolated user-listings store."
  },
  "games": {
    "default": "pokemon",
    "supported": [
      "pokemon",
      "magic",
      "yugioh",
      "flesh_and_blood",
      "digimon",
      "dragon_ball_super",
      "vanguard",
      "one_piece",
      "lorcana",
      "star_wars",
      "union_arena",
      "riftbound",
      "gundam",
      "sorcery",
      "palworld",
      "cyberpunk"
    ],
    "query": "game (alias marketplaceGame)",
    "headers": [
      "x-pokoin-game",
      "x-marketplace-game"
    ],
    "resolution": "Non-Pokemon query scope first, then game header, then recognized forwarded/site hostname. Unknown game values normalize to pokemon.",
    "rule": "Carry the selected game across search, detail, expansion, portfolio and listing requests. Public IDs returned by the API are already normalized."
  },
  "listings": {
    "path": "/api/marketplace-listings",
    "methods": [
      "GET",
      "POST",
      "PATCH"
    ],
    "publicRead": "GET with cardId (public id), game and limit (default 500, max 1000). nativeOnly=1 or live=0 skips live CardTrader. Response: {listings:[]}.",
    "sellerRead": "sellerUid requires a Firebase bearer token matching the owner UID. sellerUsername reads active public seller inventory. Do not pass both.",
    "write": "POST creates; PATCH?id=<listing-id> updates. Firebase bearer required; ownership and reserve privileges are checked server-side.",
    "gameScope": "Native marketplace_user_listings is the shared central store; catalog/game tags scope seller inventory. Clients must send game and must not choose a database.",
    "cache": "private, no-store"
  },
  "payments": {
    "currency": "PKN for marketplace values",
    "authority": "Prices, balances, ownership and privileges are checked by the server. Client totals are not payment authority.",
    "discovery": "See routes for marketplace-checkout-quote, create-order-checkout-session, marketplace-orders, create-pkn-checkout-session and stripe-webhook; availability is determined by the running manifest."
  },
  "health": {
    "path": "GET /healthz (alias /api/healthz)",
    "dependencies": [
      "Postgres",
      "Valkey",
      "Meilisearch",
      "CDN"
    ],
    "unhealthyStatus": 503
  },
  "errors": {
    "pipelinePolicy": {
      "status": 503,
      "body": {
        "error": "We are working on a solution."
      }
    },
    "handlerErrors": "Validation, auth and not-found errors retain their handler HTTP status. Some handlers still return 500 errors or degraded 200 payloads; do not assume every failure is normalized to the pipeline policy.",
    "suggest": "Empty/degraded suggestions may include meta.reason; an empty popup alone is not proof that no catalog matches exist."
  },
  "compatibility": {
    "flutterUsage": "docs/flutter-api-usage.json is a repository audit snapshot, not the running route count.",
    "deploymentNote": "Contract metadata follows the 2026-10-01 public reference. Each release derives routes and routeCount from its own server manifest; matching contract versions do not guarantee identical installed routes or business logic. Updating this file does not deploy production."
  }
};

function buildClientContract(routes = routeDefinitions) {
  const contract = JSON.parse(JSON.stringify(CLIENT_REFERENCE));
  contract.navigation.families = FAMILIES.map(({ id }) => id);
  contract.routes = routes.map((route) => ({
    path: route.path,
    methods: [...route.methods],
    family: familyForPath(route.path),
    purpose: route.purpose,
    auth: route.auth,
    params: JSON.parse(JSON.stringify(route.params || {})),
    ...(route.rawBody ? { rawBody: true } : {}),
  }));
  contract.routeCount = contract.routes.length;
  return contract;
}

const CLIENT_CONTRACT = buildClientContract();

module.exports = { CLIENT_CONTRACT, buildClientContract };
