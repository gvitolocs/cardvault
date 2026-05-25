# Pokemon Card Extension API Handoff

Share this document with agents working in `/Users/giuseppe/pokemon-card-extension`.
It reflects the current Pokoin/Cardvault API contract and the recent extension
workflow notes read from:

- `docs/EXTENSION_WORKFLOW.md`
- `docs/EXTENSION_AGENT_HANDOFF.md`
- `docs/API_INTEGRATION.md`
- `docs/POKOIN_AUTH_CARDMARKET_BLOCKER.md`

Do not modify the extension repo from this handoff unless the extension task
explicitly asks for it.

## Base URLs

Production:

```text
https://pokoin.com
```

Local Cardvault development:

```text
http://localhost:3000
```

## Auth Bridge

The extension cannot read the Pokoin web Firebase session from marketplace
origins. It should open or reuse:

```text
GET https://pokoin.com/extension/auth-bridge
```

When a Pokoin user is signed in, the page posts a JSON string to
`window.opener` and `window.parent`, then calls `window.close()`:

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

- Accept both object messages and JSON-string messages.
- Accept messages only from `https://pokoin.com`.
- Read `token.accessToken`; do not read `token.token`.
- Store the bearer in `chrome.storage.session`, not `chrome.storage.local`.
- Do not expose bearer tokens to marketplace content scripts.
- Attach the token to authenticated API calls as
  `Authorization: Bearer <firebase-id-token>`.
- If the bridge reports `status: "signed_out"`, open
  `https://pokoin.com/auth?from=extension&closeOnAuth=1`.
- On a `401`, force-refresh the bridge once and retry the failed request.

Token validation endpoint:

```text
POST https://pokoin.com/api/auth-login
Authorization: Bearer <firebase-id-token>
```

Success:

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

Common auth errors are JSON:

```json
{ "error": "Missing Pokoin bearer token." }
```

```json
{ "error": "Firebase ID token has expired." }
```

## Extension Card Search

Main structured search endpoint:

```text
POST https://pokoin.com/api/extension-card-search
Content-Type: application/json
```

Auth: none.

Preferred request:

```json
{
  "name": "Mew",
  "collectorNumber": "232/091",
  "expansion": "Paldean Fates",
  "rarity": "Special Illustration Rare",
  "rarityAliases": ["Illustration Rare", "Special Illustration Rare"],
  "variation": "ex",
  "language": "en",
  "limit": 3
}
```

Accepted aliases:

```text
name: name, cardName, pokemonName
collectorNumber: collectorNumber, collectionNumber, number, cardNumber
expansion: expansion, expansionName, set, setName
rarity: rarity, cardRarity
rarityAliases: rarityAliases, rarity_aliases, cardRarityAliases
variation: variation, variant, cardVariant
language: language, search_language, lang
limit: limit, result_limit, resultLimit
```

Response:

```json
{
  "query": "Mew ex 232/091 Paldean Fates Special Illustration Rare",
  "input": {
    "name": "Mew",
    "collectorNumber": "232/091",
    "expansion": "Paldean Fates",
    "rarity": "Special Illustration Rare",
    "rarityAliases": ["Illustration Rare", "Special Illustration Rare"],
    "variation": "ex"
  },
  "source": "structured_fields",
  "language": "en",
  "matches": [
    {
      "cardId": "274416",
      "name": "Mew ex",
      "expansionName": "Paldean Fates",
      "collectorNumber": "Special Illustration Rare | 232/091",
      "rarity": "Special Illustration Rare",
      "cardType": "Trading card",
      "itemKind": "single",
      "productType": "card",
      "trainerName": "",
      "imageUrl": "https://cdn.pokoin.com/274416_mew-ex-special-illustration-rare-232-091-paldean-fates.jpg",
      "previewImageUrl": "https://cdn.pokoin.com/previews/274416_mew-ex.jpg",
      "cardPalette": {},
      "emoji": "",
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

Use the first item in `matches` as the best backend-ranked candidate. Keep
extension lookup limits small; `3` is enough for exact lookups and `8` is enough
for overlay previews.

Search accuracy rules:

- Prefer structured fields over one raw `query`.
- Preserve full printed collector numbers such as `232/091`, `TG16/TG30`,
  `RC32/RC32`, `SV-P 129`, `DRS 009`, `HL 9`, and `MEP 042`.
- Numeric collector matching is a fallback only; exact printed/prefixed evidence
  should outrank numeric-only equivalence.
- Keep real variants in `variation`, such as `Mega`, `X`, `Y`, `ex`, `V`,
  `VMAX`, `VSTAR`, `GX`, and `LV.X`.
- Send real rarity text in `rarity`.
- If the UI has a simple `illustration` chip, send
  `rarityAliases: ["Illustration Rare", "Special Illustration Rare", "full art", "illustration"]`.
- Do not send artist credits as rarity, variation, or query text.
  `Illus.`, `Illustrator:`, and `Artist:` are treated as artist labels and are
  stripped by the API. They do not mean `Illustration Rare`.
- Keep actual `Illustration Rare`, `Special Illustration Rare`, `IR`, and `SIR`
  rarity evidence.
- Trust the order returned by Pokoin for typed/exact results. Price enrichment
  and fallback autocomplete must not reorder stronger selected-key rows.

## Blueprint Price API

Use this for Pokoin PKN listing price enrichment. It replaces the old
`/api/cardtrader-redirect?id=...` price-enrichment workaround.

```text
GET https://pokoin.com/api/marketplace-blueprint-price?blueprintId=274416
```

`cardId` is accepted as an alias:

```text
GET https://pokoin.com/api/marketplace-blueprint-price?cardId=274416
```

Auth: none.

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

No active listing:

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

The no-listing response uses HTTP `404`; treat it as "no active Pokoin seller
price", not as a failed card match.

## Fallback Autocomplete

Fallback endpoint:

```text
POST https://pokoin.com/api/marketplace-autocomplete
Content-Type: application/json
```

Auth: none for normal extension fallback search.

Example:

```json
{
  "search_term": "sprigatito illustration",
  "result_limit": 8,
  "pool_limit": 1000,
  "search_language": "en"
}
```

Use this after exact selected-key or structured extension search is unavailable
or insufficient. Do not merge fallback rows above exact rows for the same
selected clue signature.

## Canonical Card URLs

New share links and side-panel iframe links should use the canonical marketplace
URL returned by `marketplaceUrl`/`canonicalUrl` from `/api/extension-card-search`.

Shape:

```text
/marketplace/{lang}/cards/{blueprintId * 2}/{rarity-name-number-set}
```

Examples:

```text
https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates
https://pokoin.com/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions
```

Legacy numeric links still resolve:

```text
/marketplace/en/cards/274416
/marketplace/en/cards/316600-leafeon-005-131-prismatic-evolutions
/129834
```

Legacy links canonicalize after the card payload loads. New extension links
should not use `/card/:id`, root numeric short links, or old
`/marketplace/en/cards/:id` links when the API has supplied a canonical URL.

## Cardmarket Observations

Endpoint:

```text
POST https://pokoin.com/api/cardmarket-scrape-observation
Authorization: Bearer <firebase-id-token>
Content-Type: application/json
```

The extension should send observations only after rendering/search work is not
blocked. If auth is missing, queue a bounded session-only pending observation,
open/reuse the auth bridge, and flush after a token arrives.

Payload:

```json
{
  "url": "https://www.cardmarket.com/en/Pokemon/Products/Singles/Dragon-Majesty/Hydreigon-DRM33",
  "title": "Hydreigon (DRM 33)",
  "hostname": "www.cardmarket.com",
  "structuredCard": {
    "rawTitle": "Hydreigon (DRM 33)",
    "name": "Hydreigon",
    "collectorNumber": "DRM 33",
    "collectorNumberPrefix": "DRM",
    "numericCollectorNumber": "33",
    "expansion": "Dragon Majesty"
  },
  "cardmarketContext": {
    "expansion": "Dragon Majesty"
  },
  "match": {
    "cardId": "114322",
    "relevanceScore": 0.98,
    "name": "Hydreigon"
  },
  "promoteVerifiedLink": false,
  "extensionVersion": "2.0.0",
  "source": "pokemon-card-extension"
}
```

Rules:

- A top-level `url`, `cardmarketUrl`, or `pageUrl` is required.
- Use `promoteVerifiedLink: true` only for exact confident Cardmarket product
  matches where URL, name, collector number, expansion, and selected Pokoin card
  agree.
- Navigation/search observations should use `promoteVerifiedLink: false`.
- Observation failures must not leave the side panel loading or replace exact
  candidate rows.

Success:

```json
{
  "ok": true,
  "observation": {
    "id": "<uuid>",
    "status": "matched",
    "observed_at": "2026-05-21T09:49:20.878Z"
  },
  "verifiedLink": null
}
```

## CORS

These extension-facing APIs answer preflight:

```text
OPTIONS /api/extension-card-search
OPTIONS /api/marketplace-blueprint-price
OPTIONS /api/auth-login
OPTIONS /api/cardmarket-scrape-observation
OPTIONS /api/marketplace-autocomplete
```

They return `204` with:

```text
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
```

Allowed methods are endpoint-specific:

```text
extension-card-search: POST, OPTIONS
marketplace-blueprint-price: GET, OPTIONS
auth-login: POST, OPTIONS
cardmarket-scrape-observation: POST, OPTIONS
marketplace-autocomplete: POST, OPTIONS
```

## Error Shapes

Errors are JSON:

```json
{ "error": "Method not allowed." }
```

```json
{ "error": "Missing or invalid blueprintId." }
```

```json
{ "error": "No active PKN listing price found for this blueprint." }
```

```json
{ "error": "A valid Cardmarket singles URL is required." }
```

```json
{ "error": "Firebase ID token has expired." }
```

If a Vercel/runtime failure happens before the handler starts, the platform may
return non-JSON. Extension code should show a generic retryable API message in
that case.

## Vinted Query Notes

For Vinted side-panel external search buttons, keep the recent Cardvault rule:
preserve the full card name first, add only a leading collector number when it
fits, and keep the total query budget short, about 14 characters. Do not append
long expansion names.

## Remaining Extension Repo Changes

- Switch price enrichment from
  `GET /api/cardtrader-redirect?id=<blueprintId>` to
  `GET /api/marketplace-blueprint-price?blueprintId=<blueprintId>`.
- Prefer `marketplaceUrl` or `canonicalUrl` from extension search matches for
  side-panel iframe/share links instead of constructing
  `/marketplace/en/cards/<id>` locally.
- Preserve `rarityAliases` for the `illustration` chip. Backend support now
  accepts this payload shape.
- Keep the auth bridge parser accepting JSON-string payloads and
  `token.accessToken`.
- Keep Cardmarket observation payloads with a top-level `url` and
  `source: "pokemon-card-extension"`.
- Store artist/illustrator labels only as artist/debug metadata. Do not include
  `Illus.`, `Illustrator:`, or `Artist:` in `rarity`, `variation`, or `query`.
- Ensure local/fallback ranking never replaces exact selected-key rows for the
  same URL/signature. Price enrichment is decoration only.
- Rebuild the packaged extension zip after runtime file changes and run the
  extension hash guard.

## Cardvault Verification

Run from `/Users/giuseppe/cardvault/pokemon_card_vault`:

```bash
node --check api/extension-card-search.js
node --check api/marketplace-blueprint-price.js
node --check api/auth-login.js
node --check api/marketplace-autocomplete.js
node --check api/cardmarket-scrape-observation.js
node --test api/extension-card-search.test.js api/marketplace-blueprint-price.test.js api/auth-login.test.js api/marketplace-autocomplete.test.js
git diff --check -- api/extension-card-search.js api/extension-card-search.test.js api/marketplace-autocomplete.js api/marketplace-autocomplete.test.js api/marketplace-blueprint-price.js api/auth-login.js api/cardmarket-scrape-observation.js docs/extension-card-search-api.md docs/EXTENSION_AGENT_HANDOFF.md docs/pokoin-api.md
```
