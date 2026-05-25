# Extension Search Parity Report

Agent-facing report for the agent working in `/Users/giuseppe/pokemon-card-extension`.
This documents the current Cardvault/Pokoin search behavior and the work needed
for the extension to behave locally like the Flutter marketplace searchbar.

## Sources Inspected

Cardvault/Pokoin:

- `lib/providers/card_provider.dart`
- `lib/services/card_service.dart`
- `lib/screens/home_screen.dart`
- `api/marketplace-autocomplete.js`
- `api/marketplace-search-candidates.js`
- `api/extension-card-search.js`
- `api/marketplace-blueprint-price.js`
- `docs/EXTENSION_AGENT_HANDOFF.md`
- `docs/extension-card-search-api.md`
- `docs/pokoin-api.md`
- `workflows/cardtrader-search-preview-workflow.md`
- `workflows/oracle-marketplace-postgres-workflow.md`

Extension:

- `config/background.js`
- `config/api-config.js`
- `pokoin-auth-bridge.js`
- `processors/VINT.js`
- `processors/EBAYE.js`
- `processors/CME.js`
- `ui-pages/sidepanel.js`
- `docs/API_INTEGRATION.md`
- `docs/EXTENSION_AGENT_HANDOFF.md`
- `docs/EXTENSION_WORKFLOW.md`
- `tests/cardvault-api-smoke.test.js`
- `tests/extension-workflow.test.js`

## Executive Summary

The Cardvault backend already has the capabilities needed for extension search
parity: structured card lookup, server-ranked autocomplete with lightweight
`search_context`, canonical public-number marketplace URLs, public CORS for
extension-facing endpoints, a bearer-token auth bridge for protected observation
writes, and a public blueprint price endpoint.

The extension already has a strong selected-chip workflow and calls
`/api/extension-card-search` before fallback autocomplete. It preserves many
important clues: name, variation, collector number, expansion, feature/rarity
chips, `rarityAliases`, and Cardmarket exact identity. The main parity gaps are:

- The extension does not yet implement the Flutter searchbar's local searchbox
  lifecycle: empty-focus hot 1000 pool, first-character backend warmup, top-1000
  typed/context pool, 20 rendered rows, recent top 2, and context-forwarded
  incremental refinement.
- The extension fallback autocomplete calls are fresh calls; they do not forward
  `previous_search_context`, hold compatible prefix pools, or use the backend
  context bridge the way Flutter does.
- Side-panel and helper URL generation still falls back to
  `/marketplace/en/cards/<blueprintId>` in several places instead of preferring
  `canonicalUrl` / `marketplaceUrl` from `/api/extension-card-search`.
- Price enrichment in `config/background.js` still calls
  `/api/cardtrader-redirect?id=<id>` and parses CardTrader-shaped product prices.
  It should use `/api/marketplace-blueprint-price?blueprintId=<id>`.
- Some display helpers intentionally truncate collector numbers for compact UI.
  That is acceptable for display only, but search payloads and ranking inputs
  must continue preserving full printed collector values such as `085/131`,
  `SV-P 129`, `DRS 009`, `HL 9`, and `TG16/TG30`.

No Cardvault API code changes appear necessary for this parity pass.

## Current Cardvault Backend Capabilities

### `/api/marketplace-autocomplete`

Purpose: Flutter searchbar and extension fallback autocomplete. It is the final
ranker for typed preview rows.

Request:

```json
{
  "search_term": "mew ex 216",
  "result_limit": 20,
  "pool_limit": 5000,
  "search_language": "en",
  "previous_search_context": null,
  "search_session_id": "extension-1716400000000-1"
}
```

Response shape:

```json
{
  "rows": [
    {
      "card_id": "274416",
      "name": "Mew ex",
      "set_name": "Paldean Fates",
      "card_number": "Special Illustration Rare | 232/091",
      "rarity": "Special Illustration Rare",
      "item_kind": "single",
      "product_type": "card",
      "trainer_name": "",
      "preview_image_url": "https://cdn.pokoin.com/previews/274416_mew-ex.jpg",
      "search_rank": 16762.03
    }
  ],
  "pool": {
    "source": "search_pipeline",
    "size": 500,
    "limit": 5000,
    "previewLimit": 20,
    "strategy": "candidate_context_refine"
  },
  "search_context": {
    "query": "mew ex 216",
    "language": "en",
    "card_ids": ["274416"],
    "created_at_ms": 1716400000000,
    "strategy": "candidate_context_refine",
    "candidate_id_ladder": {
      "requestedLimit": 5000,
      "appliedLimit": 5000
    },
    "non_name_context": {
      "depth_scores": { "274416": 8 },
      "latest_depths": { "274416": 8 },
      "latest_orders": { "274416": 0 }
    },
    "candidate_labels": [
      {
        "id": "274416",
        "name": "Mew ex",
        "item_kind": "single",
        "product_type": "card",
        "set_name": "Paldean Fates",
        "number": "Special Illustration Rare | 232/091",
        "trainer_name": ""
      }
    ]
  }
}
```

Important behavior:

- Empty focus can be backed by an empty autocomplete request or
  `/api/marketplace-hot-blueprints?includeCards=1&limit=1000`.
- One meaningful character starts backend warmup, but Flutter keeps the typed
  popup hidden.
- Typed visible rows are capped at 20. Flutter shows about 9 rows in the viewport.
- Candidate ID pool ladder is depth-dependent:
  - 1 char: backend warmup / hot one-character path, no broad full local pool.
  - 2 chars: target `5000` IDs/labels.
  - 3 chars: target `2500` IDs/labels and open visible typed popup.
  - 4 chars: target `1250`.
  - 5+ chars: target `500`.
- `previous_search_context` is valid only when the next query extends the
  previous query, language is unchanged, IDs are bounded, and context is fresh
  (about 60 seconds).
- Backend ranking handles canonical names, localized names, trainer-owned names,
  variation tokens, collector numbers, expansion/set aliases, rarity aliases,
  analytics boosts, and context-depth ranking inside the matched candidate pool.

### `/api/extension-card-search`

Purpose: extension structured lookup from scraped fields or selected clue chips.
This should remain the first exact path for listing/product pages.

Preferred request:

```json
{
  "name": "Mew",
  "collectorNumber": "232/091",
  "expansion": "Paldean Fates",
  "rarity": "Special Illustration Rare",
  "rarityAliases": ["Illustration Rare", "Special Illustration Rare", "full art", "illustration"],
  "variation": "ex",
  "language": "en",
  "limit": 8
}
```

Response:

```json
{
  "query": "Mew ex 232/091 Paldean Fates Special Illustration Rare",
  "source": "structured_fields",
  "language": "en",
  "matches": [
    {
      "cardId": "274416",
      "name": "Mew ex",
      "expansionName": "Paldean Fates",
      "collectorNumber": "Special Illustration Rare | 232/091",
      "rarity": "Special Illustration Rare",
      "itemKind": "single",
      "productType": "card",
      "trainerName": "",
      "previewImageUrl": "https://cdn.pokoin.com/previews/274416_mew-ex.jpg",
      "marketplacePath": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "marketplaceUrl": "https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "canonicalPath": "/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "canonicalUrl": "https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates",
      "score": 16762.03,
      "relevanceScore": 16430,
      "analyticsBoost": 332.03
    }
  ]
}
```

Rules:

- Trust `matches` order. The first match is the backend-ranked best candidate.
- Preserve `marketplaceUrl` / `canonicalUrl` on extension rows and side-panel
  state. New links should not construct `/marketplace/en/cards/<id>` when the
  API supplied canonical public-number URLs.
- `cleanExtensionQuery` strips `Illus.`, `Illustrator:`, and `Artist:` labels.
  The extension should also keep artist labels out of `query`, `rarity`, and
  `variation`.
- `rarityAliases` is already supported for simple UI chips such as
  `illustration`.

### `/api/marketplace-blueprint-price`

Purpose: public Pokoin PKN price enrichment for a blueprint/card ID.

Request:

```text
GET https://pokoin.com/api/marketplace-blueprint-price?blueprintId=274416
```

Success:

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

No active listing: HTTP `404` with the same shape and `price_pkn: null`. Treat
that as "no active Pokoin seller price", not as a search failure.

### `/extension/auth-bridge`

Purpose: extension obtains a Firebase ID token for authenticated APIs without
exposing the token to marketplace content scripts.

Bridge URL:

```text
GET https://pokoin.com/extension/auth-bridge
```

Expected message from Pokoin:

```json
{
  "type": "pokoin-auth-token",
  "ok": true,
  "status": "authenticated",
  "token": {
    "accessToken": "<firebase-id-token>",
    "tokenType": "Bearer",
    "uid": "<firebase-uid>",
    "email": "collector@example.com"
  }
}
```

Extension requirements:

- Accept object messages and JSON-string messages.
- Accept only from `https://pokoin.com`.
- Read `token.accessToken`.
- Store tokens in `chrome.storage.session`, never `chrome.storage.local`.
- Attach `Authorization: Bearer <token>` only in background/service-worker calls
  to protected APIs, such as `/api/cardmarket-scrape-observation`.
- On `401`, force-refresh the bridge once and retry the failed request.

## Flutter Searchbar Behavior To Mirror

Flutter implementation details from `CardNotifier` and `CardService`:

- Constants:
  - `searchPreviewLimit = 20`
  - `searchPreviewVisibleRows = 9`
  - `searchPreviewWarmupChars = 1`
  - `searchPreviewVisibleChars = 3`
  - `searchPreviewHotCacheLimit = 1000`
  - Prefix pool history cap: 16 pools and 20,000 aggregate IDs.
- Empty focus:
  - Uses the hot 1000 server/cache pool.
  - Prepends up to the user's top 2 recent blueprints.
  - Renders the first 20 rows.
  - Does not create a typed search session until the user types.
- Typed search:
  - First meaningful character starts a backend search session and debounced
    `/api/marketplace-autocomplete` warmup.
  - The visible typed popup stays closed until 3 meaningful characters.
  - Typing clears empty-focus hot rows immediately. No unrelated hot rows may
    remain while typed results are loading.
  - Stale responses are dropped by request ID.
  - The latest valid `search_context` is retained and sent back only when the
    next query extends the previous query with the same language.
  - During an in-flight request, Flutter may render a local bridge only from
    compatible historical prefix pools and current `search_context.card_ids` /
    `candidate_labels`, capped to 20.
  - It does not rank or store thousands of full card objects locally.
- Ranking:
  - Completed backend rows are authoritative.
  - Deduplication preserves response order.
  - No local alphabetical sorting for typed preview/full-search results.
  - Local bridge ranking, when needed, is restricted to the backend-provided
    candidate IDs/labels and ranks deeper/repeated prefix matches ahead of older
    shallow pools.
- Token hierarchy:
  - Card name/canonical name first.
  - Variation and owner/trainer identity next (`ex`, `v`, `gx`, `vmax`,
    `vstar`, `lv x`, `mega`, `tag team`, `delta`, etc.).
  - Collector number next.
  - Expansion/set aliases next.
  - Rarity/rarity abbreviations next (`SIR`, `SAR`, `IR`, `UR`, etc.).
  - Artist/illustrator labels are display metadata only and must not affect
    search/ranking.

## Extension Current Implementation Status

### Already Good

- `config/background.js` calls `/api/extension-card-search` via
  `searchExtensionCard(structuredCard)` and sends structured fields:
  `name`, `collectorNumber`, `numericCollectorNumber`, `printedCollectorNumber`,
  `expansion`, `rarity`, `rarityAliases`, `variation`, and `language`.
- Vinted and eBay selected-chip payloads preserve many needed fields:
  `name`, `variation`, `variationTokens`, `collectorNumber`,
  `numericCollectorNumber`, `expansion`, `features`, `rarity`, and
  `rarityAliases`.
- Cardmarket product pages are readiness-gated and pass collector/expansion
  clues from product details.
- `pokoin-auth-bridge.js` already accepts JSON-string messages and the current
  `pokoin-auth-token` shape with `token.accessToken`.
- The background stores auth session state in `chrome.storage.session`.
- Exact selected rows are protected from later generic fallback/price updates.
- Tests cover many important smoke cases in `tests/cardvault-api-smoke.test.js`,
  including `mew 232`, `flareon ex`, `manaphy ex`, `garchomp di camilla`, and
  padded collector examples.

### Gaps To Fix

- `config/api-config.js`, `ui-pages/sidepanel.js`, and `config/background.js`
  still construct numeric marketplace URLs such as
  `https://pokoin.com/marketplace/en/cards/<blueprintId>`. Preserve and prefer
  canonical URLs returned by `/api/extension-card-search`:
  `canonicalUrl`, `marketplaceUrl`, `canonicalPath`, or `marketplacePath`.
- `config/background.js` still enriches prices by calling
  `/api/cardtrader-redirect?id=<blueprintId>`. Replace that with
  `/api/marketplace-blueprint-price?blueprintId=<blueprintId>` and format
  `price_pkn` as a PKN value.
- Fallback autocomplete functions call `/api/marketplace-autocomplete` but do not
  maintain a Flutter-style search session, `previous_search_context`, prefix-pool
  history, or the 20-from-1000 typed rendering contract.
- The extension overlay previews are selected-key driven, not currently a local
  searchbar clone. If the product requirement is a local searchbox in the
  extension, add a dedicated state module rather than expanding one-off processor
  fallback calls.
- Compact display helpers such as `firstCollectorNumber` intentionally show only
  the first collector number. Keep that display behavior separate from search
  payloads. Do not feed truncated values back into search/ranking.
- Current docs still mention `/api/cardtrader-redirect` as the price endpoint.
  Update extension docs when code is changed.

## Target Extension Architecture

Add a small search adapter owned by the background service worker, with UI state
consumed by the overlay/side panel:

```text
processor/overlay input
  -> extension search adapter
    -> empty focus hot/recent path OR typed autocomplete path
    -> /api/extension-card-search for selected exact structured rows
    -> /api/marketplace-autocomplete for typed/fallback candidate pools
    -> /api/marketplace-blueprint-price for decoration only
  -> UI renders backend-ordered rows
```

Recommended module boundary:

- Keep marketplace-specific parsing in `processors/VINT.js`, `processors/EBAYE.js`,
  and `processors/CME.js`.
- Keep API calls and ranking/cache state in `config/background.js` or extract to a
  background-owned helper file if the extension build allows it.
- Keep side panel rendering in `ui-pages/sidepanel.js`; it should display the
  ranked rows it receives and prefer row canonical URLs.

### Empty Focus

If the extension has a local search field:

1. On focus with empty query, request either:

```json
{
  "search_term": "",
  "result_limit": 20,
  "pool_limit": 1000,
  "search_language": "en"
}
```

or call:

```text
GET /api/marketplace-hot-blueprints?includeCards=1&limit=1000
```

2. Cache the hot pool in session memory.
3. Prepend up to 2 recent extension/Pokoin blueprints when they are relevant.
4. Render only 20 rows.
5. Clear these rows immediately when typing starts.

### Typed Autocomplete

For each active searchbox session:

1. Create a search session id, for example
   `extension-${Date.now()}-${sequence}`.
2. Debounce typed input similarly to Flutter (`120ms` is the Flutter preview
   debounce; extension can use nearby values if UI constraints require).
3. For every query with at least 1 meaningful character, POST:

```json
{
  "search_term": "pik",
  "result_limit": 20,
  "pool_limit": 2500,
  "search_language": "en",
  "search_session_id": "extension-1716400000000-1",
  "previous_search_context": {
    "query": "pi",
    "language": "en",
    "card_ids": ["..."],
    "created_at_ms": 1716400000000,
    "strategy": "ranked_pool",
    "candidate_labels": []
  }
}
```

4. Use pool limits by meaningful-character depth:
   - `<= 1`: 1000 / backend warmup.
   - `2`: 5000.
   - `3`: 2500.
   - `4`: 1250.
   - `5+`: 500.
5. Do not show typed popup rows until 3 meaningful characters, but still warm the
   backend at 1 and 2 characters.
6. Store the latest `search_context` only if the response is current.
7. Send `previous_search_context` only when:
   - next query extends previous query,
   - language is unchanged,
   - context is fresh,
   - context has bounded card IDs.
8. Drop stale responses by request id.
9. Deduplicate by exact `card_id` while preserving backend order.
10. Never append unrelated hot rows after typing starts.

### Selected Exact Search

For marketplace listing/product pages, keep the current selected-key-first path:

1. Build a structured payload from selected chips and page identity.
2. Call `/api/extension-card-search`.
3. Accept backend-ranked matches after local sanity filters for selected exact
   identity.
4. Use fallback autocomplete only when exact rows are empty or weak.
5. Never let fallback autocomplete or price enrichment replace a strong exact row
   for the same URL/signature.

## Local Ranking And Cache Rules

Do:

- Trust backend order from `/api/extension-card-search` and
  `/api/marketplace-autocomplete`.
- Preserve row order after dedupe.
- Render only the first 20 searchbar candidates; let the UI scroll if it shows
  fewer rows at a time.
- Use local context only as a bridge while a newer request is in flight.
- Restrict bridge rows to backend-provided `card_ids` and `candidate_labels`.
- Keep recent views only for empty-focus rows.
- Keep price enrichment as decoration.

Do not:

- Do not alphabetically sort typed results.
- Do not append generic hot rows once the user has typed.
- Do not merge loaded/cached local cards into typed autocomplete.
- Do not use artist, illustrator, or `Illus.` labels as rarity/query/variation.
- Do not truncate collector numbers for search payloads.
- Do not let `085/131` become only `085` in API requests.
- Do not let `85-131` lose the denominator if the original text provides it.
- Do not treat expansion text like `GX Battle Boost` as proof of a `GX`
  variation when the card identity does not have `GX`.
- Do not replace selected exact rows with price-enriched/fallback rows.

## File-Level TODO Checklist For Extension Agent

1. `config/background.js`
   - Replace `fetchPokoinListingPrice` use of
     `/api/cardtrader-redirect?id=<id>` with
     `/api/marketplace-blueprint-price?blueprintId=<id>`.
   - Add a PKN formatter for `price_pkn` and tolerate 404/null price as no price.
   - Preserve canonical URL fields from `rowFromExtensionMatch`:
     `canonicalUrl`, `marketplaceUrl`, `canonicalPath`, `marketplacePath`.
   - Include those fields in `legacyResultFromRow`, `selectedCandidateRowFromRequest`,
     `sidePanelRowFromPreview`, side-panel state rows, and any cached preview rows.
   - Set `pokoinUrl` from `best.canonicalUrl || best.marketplaceUrl ||
     absolute(best.canonicalPath || best.marketplacePath)` before falling back to
     `/marketplace/en/cards/<card_id>`.
   - Add a typed autocomplete/session helper if the extension UI will expose a
     searchbox: request id, session id, previous context, prefix-pool history,
     pool limit ladder, and 20-row render cap.

2. `ui-pages/sidepanel.js`
   - Change `cardUrl(row.card_id)` usage to prefer `row.canonical_url`,
     `row.canonicalUrl`, `row.marketplace_url`, `row.marketplaceUrl`,
     `row.canonical_path`, or `row.marketplacePath` before numeric fallback.
   - Keep compact collector display separate from search payloads.
   - If adding local search UI here, do not rank locally; send messages to the
     background adapter and render returned rows in order.

3. `config/api-config.js`
   - Update `generateCardTraderLink` compatibility helper to prefer canonical
     URLs when passed a row/object. If it only receives an ID, keep numeric
     fallback as compatibility.

4. `processors/VINT.js`
   - Preserve current selected-chip structured payload behavior.
   - Ensure full printed collector values are sent in `collectorNumber`.
   - Keep `illustration` chip mapped to `rarityAliases`; do not send artist text
     as rarity.
   - If overlay gets a typed searchbox, use the background search adapter rather
     than local sorting.

5. `processors/EBAYE.js`
   - Same as Vinted: keep selected name/variation/collector/expansion chips as
     primary exact evidence.
   - Add verification for `85-131` / `085/131` if eBay titles use hyphenated
     number formats.

6. `processors/CME.js`
   - Continue readiness-gated product parsing.
   - Add rarity/artist parsing only if the DOM has reliable labels. Artist labels
     must be stored as artist/debug metadata only.
   - Preserve product detail collector/expansion clues in side-panel open payloads.

7. `docs/EXTENSION_AGENT_HANDOFF.md` and `docs/API_INTEGRATION.md`
   - Replace price endpoint references to `/api/cardtrader-redirect` with
     `/api/marketplace-blueprint-price`.
   - Document canonical URL preservation.
   - Document autocomplete context forwarding if implemented.

8. Tests
   - Update `tests/extension-workflow.test.js` for canonical URL propagation and
     new price endpoint.
   - Update `tests/cardvault-api-smoke.test.js` to remove the redirect price test
     or make it explicitly about legacy CardTrader redirect only, not Pokoin price
     enrichment.
   - Add unit tests for context forwarding if a typed search adapter is added.

## Verification Cases

Backend/API behavior to preserve:

- `mew ex 216`
  - Expected: real `Mew ex` rows; collector-number intent must outrank generic
    Mew/hot rows.
- `common-fan-rotom-085-131-prismatic-evolutions`
  - Expected: Fan Rotom `085/131` from Prismatic Evolutions with canonical
    public-number URL, for example blueprint `316698` -> public number `633396`.
- `flareon ex`
  - Expected: `Flareon ex` before ordinary Flareon rows.
- `pikachu surgin`
  - Expected: Surging Sparks intent must not be beaten by `Surfing Pikachu`
    because `surgin` resembles `surfing`; inspect canonical name/trainer/set
    token handling if it fails.
- `cynthia garchomp`
  - Expected: Cynthia/Garchomp trainer-owned identity should rank above generic
    Garchomp where the backend has the trainer relationship.
- Artist blocker
  - Input with `Illus. Saya Tsuruta`, `Illustrator: ...`, or `Artist: ...`
    should not search as `illustration`, `Illustration Rare`, or a rarity token.
- Rarity aliases
  - `sprigatito illustration`, `mew sir`, `mew sar`, `mew ir`, and `mew ur`
    should narrow by rarity/alias inside the matching name/variation pool.
- Collector formats
  - Preserve and match `085/131`, `85-131` when original marketplace text uses
    hyphen as slash-like shorthand, `SV-P 129`, `DRS 009`, `HL 9`,
    `TG16/TG30`, and `RC32/RC32`.

Extension UI behavior to verify:

- Empty search focus shows hot/recent rows only, capped to 20.
- Typing one character clears empty-focus rows and starts backend warmup.
- Typed popup stays hidden until 3 meaningful characters.
- Later typed prefixes can bridge from context labels while loading, but only
  from compatible backend IDs/labels.
- Completed typed rows render in backend order.
- Side-panel iframe URL uses canonical public-number URL when available.
- Price enrichment updates only price text and never changes row order or best
  candidate.

## Suggested Request Helpers

Autocomplete helper:

```js
function poolLimitForQuery(query) {
  const depth = (String(query || '').match(/[a-z0-9]/gi) || []).length;
  if (depth <= 1) return 1000;
  if (depth === 2) return 5000;
  if (depth === 3) return 2500;
  if (depth === 4) return 1250;
  return 500;
}

function canRefineContext(context, nextQuery, language) {
  const cardIds = context?.card_ids || context?.cardIds;
  const createdAtMs = context?.created_at_ms || context?.createdAtMs;
  if (!context || !Array.isArray(cardIds) || cardIds.length === 0) {
    return false;
  }
  const previous = String(context.query || '').trim().toLowerCase();
  const next = String(nextQuery || '').trim().toLowerCase();
  const ageMs = Date.now() - Number(createdAtMs || 0);
  return previous &&
    next.startsWith(previous) &&
    next !== previous &&
    String(context.language || 'en').toLowerCase() === String(language || 'en').toLowerCase() &&
    ageMs >= 0 &&
    ageMs < 60_000;
}
```

Price helper:

```js
async function fetchPokoinListingPrice(blueprintId) {
  const response = await fetch(
    `https://pokoin.com/api/marketplace-blueprint-price?blueprintId=${encodeURIComponent(blueprintId)}`,
    { headers: { accept: 'application/json' } },
  );
  const payload = await response.json().catch(() => null);
  if (!payload || payload.price_pkn == null) return '';
  return `${Number(payload.price_pkn).toLocaleString('en-US')} PKN`;
}
```

Canonical URL helper:

```js
function absolutePokoinUrl(pathOrUrl) {
  if (!pathOrUrl) return '';
  return /^https?:\/\//i.test(pathOrUrl)
    ? pathOrUrl
    : `https://pokoin.com${String(pathOrUrl).startsWith('/') ? '' : '/'}${pathOrUrl}`;
}

function pokoinUrlForRow(row) {
  return row.canonicalUrl ||
    row.marketplaceUrl ||
    absolutePokoinUrl(row.canonicalPath || row.marketplacePath) ||
    (row.card_id ? `https://pokoin.com/marketplace/en/cards/${encodeURIComponent(row.card_id)}` : '');
}
```

## Cardvault Follow-Up

No Cardvault code changes are required for the extension parity work described
here. Keep backend verification focused on existing endpoints:

```bash
node --check api/extension-card-search.js
node --check api/marketplace-autocomplete.js
node --check api/marketplace-search-candidates.js
node --check api/marketplace-blueprint-price.js
node --test api/extension-card-search.test.js api/marketplace-autocomplete.test.js api/marketplace-blueprint-price.test.js
```

Docs-only updates only require:

```bash
git diff --check -- docs/EXTENSION_SEARCH_PARITY_REPORT.md
```
