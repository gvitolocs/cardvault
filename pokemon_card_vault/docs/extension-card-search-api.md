# Extension Card Search API

This endpoint lets the browser extension send scraped Pokemon card fields and receive the best matching Pokoin marketplace card records.

For the complete Pokoin API index, auth header format, and related marketplace endpoints, see `docs/pokoin-api.md`.

## Endpoint

Production:

```text
POST https://pokoin.com/api/extension-card-search
```

Local development:

```text
POST http://localhost:3000/api/extension-card-search
```

The endpoint supports CORS and can be called directly from the extension.

## Optional Token Identification

Before sending a full structured search, the extension can identify the likely
Pokemon/card-name token with the lightweight token prediction endpoint:

```text
GET https://pokoin.com/api/searchbar-token-predict?query=mewt&search_language=en&limit=5
POST https://pokoin.com/api/searchbar-token-predict
```

POST body:

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
  "fragment": "mewt",
  "normalized_fragment": "mewt",
  "predictions": [
    {
      "display_token": "Mewtwo",
      "normalized_token": "mewtwo",
      "confidence": 94,
      "source_rank": 1,
      "language": "en",
      "matched_prefix": "mewt",
      "card_count": 24,
      "ids_count": 24,
      "representative_card_ids": ["150"]
    }
  ]
}
```

Use `predictions[0].display_token` as the candidate card-name token only when it
extends the scraped fragment and the confidence is acceptable for the UI. Then
send that clean token as `name` to `/api/extension-card-search` alongside
collector number, expansion, rarity, variation, and language. This endpoint is
tokens-only: it does not return card rows, prices, images, labels, or full search
context, and its default response should be tiny enough for per-keystroke
extension work.

The token endpoint normalizes punctuation and special name forms the same way as
search: apostrophes/curly apostrophes, underscores, hyphens, dots, brackets,
diacritics, and spacing are compacted; ampersand tag-team names compact through
`tagteam` where available. For broad fragments such as `p`, popularity from
`card_count`/`ids_count` can rank common names above weak prefix matches; longer
fragments such as `par` favor the tighter card-name token.

## Request

Send JSON with either a ready-made `query` or the structured fields scraped from the page.

Preferred structured payload:

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

If you already have one clean combined string, you can send:

```json
{
  "query": "Mew ex 232/091 Paldean Fates",
  "limit": 3
}
```

When `query` is present, it is used for search, but the structured fields are still echoed back in `input`.

## Response

```json
{
  "query": "Mew ex 232/091 Paldean Fates",
  "input": {
    "name": "Mew",
    "collectorNumber": "232/091",
    "expansion": "Paldean Fates",
    "rarity": "Special Illustration Rare",
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

Use the first item in `matches` as the best match. If `matches` is empty, the scraped fields did not map confidently to a marketplace card.

## JavaScript Example

```js
async function searchPokoinCard(scrapedCard) {
  const response = await fetch('https://pokoin.com/api/extension-card-search', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      name: scrapedCard.name,
      collectorNumber: scrapedCard.collectorNumber,
      expansion: scrapedCard.expansion,
      rarity: scrapedCard.rarity,
      variation: scrapedCard.variation,
      language: 'en',
      limit: 3,
    }),
  });

  if (!response.ok) {
    throw new Error(`Pokoin search failed: ${response.status}`);
  }

  const data = await response.json();
  return data.matches?.[0] || null;
}
```

## Notes For The Extension

- Prefer `previewImageUrl` for thumbnails and search previews.
- Use `imageUrl` only when the user opens a larger card view.
- Prefer `marketplaceUrl`/`canonicalUrl` for side-panel iframes and share links.
  These use `/marketplace/{lang}/cards/{blueprintId * 2}/{human-slug}`.
- The API already handles fuzzy matches, expansion aliases, collector numbers, rarity text, card variations like `ex`, `V`, `VSTAR`, and hot-card ordering.
- Send real card rarity only in `rarity`. Do not send artist labels such as
  `Illus. Saya Tsuruta`, `Illustrator: ...`, or `Artist: ...`; the endpoint
  strips those labels so `Illus.` cannot be mistaken for Illustration Rare.
- If the scraper captures artist text, send/store it as separate artist metadata
  only. Do not append it to `query`, `rarity`, or `variation`.
- Keep `Illustration Rare`, `Special Illustration Rare`, `IR`, and `SIR` as
  rarity values when they are actual card rarity text.
- If the extension UI has a simple `illustration` chip, send
  `rarityAliases: ["Illustration Rare", "Special Illustration Rare", "full art", "illustration"]`.
  The backend will try alias-aware search terms and ignore artist labels inside
  aliases.
- Keep `limit` small for extension lookups. `3` is usually enough.
- Add `"https://pokoin.com/*"` to the extension permissions if the browser requires host permissions for `fetch`.

## CORS And Errors

`OPTIONS /api/extension-card-search` returns `204` with:

```text
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

Error responses are JSON:

```json
{ "error": "Method not allowed." }
```

