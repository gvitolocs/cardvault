# Pokemon Card Extension Auth + Cardmarket API Handoff

Give this document to agents working in `pokemon-card-extension`.

## Goal

The extension currently calls public Pokoin endpoints, but it does not share the
current logged-in Pokoin session. Add a small auth bridge so the extension can
obtain the same Firebase bearer token used by the logged-in Pokoin web app, then
send authenticated Cardmarket scrape observations to Pokoin.

Current blocker found on 2026-05-21:

- Pokoin auth bridge sends `token.accessToken`.
- `pokemon-card-extension/pokoin-auth-bridge.js` was checking
  `token.token`.
- The extension observation payload should include a top-level `url`; Pokoin's
  observation API requires `url`, `cardmarketUrl`, or `pageUrl`.

The extension repo has a dedicated handoff:
`docs/POKOIN_AUTH_CARDMARKET_BLOCKER.md`.

## Existing Pokoin Token Shape

Pokoin web uses Firebase Auth ID tokens.

The web app sends API auth as:

```http
Authorization: Bearer <firebase-id-token>
```

Relevant Pokoin code:

- `lib/services/pokoin_api_auth.dart`
- `lib/services/pokoin_api_client.dart`

`PokoinApiAuthService.currentToken()` returns:

```json
{
  "accessToken": "<firebase-id-token>",
  "tokenType": "Bearer",
  "uid": "<firebase-uid>",
  "email": "user@example.com"
}
```

The token is also cached inside the Pokoin web origin with keys:

```text
pokoin_api_bearer_token
pokoin_api_bearer_uid
```

Do not try to read those keys directly from a Cardmarket content script. They
belong to the `https://pokoin.com` origin.

## Required Extension Auth Bridge

Implement this flow in `pokemon-card-extension`:

1. The extension opens or reuses the Pokoin-owned auth bridge:
   `https://pokoin.com/extension/auth-bridge`.
2. That Pokoin page runs in the Pokoin origin and asks Firebase Auth for the
   current ID token.
3. The Pokoin page returns a JSON string to the extension using
   `window.postMessage`. The message has `type: "pokoin-auth-token"`.
4. When authenticated, `/extension/auth-bridge` calls `window.close()` after
   posting the token. No `closeOnAuth` query parameter is required for this
   bridge route. Chrome only permits scripts to close tabs/windows they opened,
   so keep a fallback in the extension UI for users who opened the tab manually.
5. The extension background service worker stores the token in
   `chrome.storage.session`.
6. API calls that require the logged-in Pokoin session attach:

```js
headers: {
  'Content-Type': 'application/json',
  Authorization: `Bearer ${token}`,
}
```

Do not store the bearer token in `chrome.storage.local`; use session storage and
refresh when needed.

If `/extension/auth-bridge` reports `status: "signed_out"`, open the normal
Pokoin auth page with close-on-auth enabled:

```text
https://pokoin.com/auth?from=extension&closeOnAuth=1
```

After sign-in, the normal `/auth` page posts a JSON string with
`type: "pokoin-auth-complete"` to `window.opener` and `window.parent`, then calls
`window.close()`. Plain `/auth` does not auto-close; `from=extension`,
`closeOnAuth=1`, or `extension=1` is required. `extension=1` is also supported
as an equivalent marker.

## Suggested Extension Files

Likely places to edit:

- `config/background.js`: owns reliable API calls and side-panel state.
- `config/api-config.js`: keep base URL constants here.
- `ui-pages/sidepanel.js`: can request token refresh when the side panel opens.
- `manifest.json`: already has `https://pokoin.com/*` host permission.

Suggested background helper:

```js
async function getPokoinBearerToken({ forceRefresh = false } = {}) {
  const cached = await chrome.storage.session.get([
    'pokoinBearerToken',
    'pokoinBearerTokenFetchedAt',
  ]);
  const ageMs = Date.now() - Number(cached.pokoinBearerTokenFetchedAt || 0);
  if (!forceRefresh && cached.pokoinBearerToken && ageMs < 45 * 60 * 1000) {
    return cached.pokoinBearerToken;
  }

  // Open/reuse https://pokoin.com/extension/auth-bridge and receive its
  // postMessage response. Pass forceRefresh=1 when needed.
  const token = await requestTokenFromPokoinAuthBridge(forceRefresh);
  await chrome.storage.session.set({
    pokoinBearerToken: token,
    pokoinBearerTokenFetchedAt: Date.now(),
  });
  return token;
}
```

If an authenticated API returns `401`, force-refresh the token once and retry.

## New Cardmarket API

The Pokoin API endpoint is:

```text
POST https://pokoin.com/api/cardmarket-scrape-observation
```

It stores browser-collected Cardmarket product-page data in:

```sql
public.marketplace_cm_scrape_observations
```

The full Cardmarket product URL is always stored in:

```sql
marketplace_cm_scrape_observations.cardmarket_url
```

If the payload includes `promoteVerifiedLink: true` and a matched blueprint id,
the API also upserts the same full URL into the fast verified table:

```sql
public.marketplace_cm_verified_links
```

That table powers fast exact Cardmarket redirects:

```text
blueprint_id -> cardmarket_url
```

## Cardmarket Payload

The extension already knows how to parse Cardmarket pages:

- `config/background.js` reads `.page-title-container h1`.
- It reads `h1 span`, breadcrumbs, and URL path for expansion context.
- It parses titles like `Piplup (MEP 042)` into structured fields.
- `processors/CME.js` detects Cardmarket product pages.

After the extension resolves candidates, post an observation like:

```js
async function postCardmarketObservation(pageInfo, bestMatch, options = {}) {
  const token = await getPokoinBearerToken({ forceRefresh: false });
  const structured = pageInfo.structuredCard || {};
  const context = pageInfo.debug?.cardmarketContext || {};

  const response = await fetch(
    'https://pokoin.com/api/cardmarket-scrape-observation',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        url: pageInfo.url,
        title: pageInfo.title,
        hostname: pageInfo.hostname,
        structuredCard: structured,
        cardmarketContext: context,
        match: bestMatch
          ? {
              cardId: bestMatch.cardId || bestMatch.blueprint_id,
              relevanceScore: bestMatch.relevanceScore || bestMatch.score,
              name: bestMatch.name || bestMatch.name_en,
              expansionName: bestMatch.expansionName || bestMatch.expansion_name_en,
              collectorNumber: bestMatch.collectorNumber || bestMatch.card_number,
            }
          : null,
        promoteVerifiedLink: options.promoteVerifiedLink === true,
        extensionVersion: chrome.runtime.getManifest().version,
        source: 'pokemon-card-extension',
      }),
    },
  );

  if (response.status === 401 && !options.retried) {
    await getPokoinBearerToken({ forceRefresh: true });
    return postCardmarketObservation(pageInfo, bestMatch, {
      ...options,
      retried: true,
    });
  }

  if (!response.ok) {
    throw new Error(`Cardmarket observation failed: ${response.status}`);
  }
  return response.json();
}
```

## Promotion Rules

Use `promoteVerifiedLink: true` only when the extension/user is confident the
matched blueprint is the exact card:

- Cardmarket URL is a canonical `/Pokemon/Products/Singles/...` product URL.
- Card name matches.
- Collector number matches.
- Expansion matches or maps cleanly to the known Pokoin/CardTrader expansion.

For normal background observations, use:

```json
{ "promoteVerifiedLink": false }
```

Those rows still help debugging and future manual promotion, but they do not
become redirect fast-path links.

## API Response

Successful response:

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

When promoted:

```json
{
  "ok": true,
  "observation": {
    "id": "<uuid>",
    "status": "matched",
    "observed_at": "2026-05-21T09:49:20.878Z"
  },
  "verifiedLink": {
    "blueprint_id": "114322",
    "cardmarket_locale": "en",
    "cardmarket_url": "https://www.cardmarket.com/en/Pokemon/Products/Singles/Dragon-Majesty/Hydreigon-DRM33"
  }
}
```

## Testing Checklist

1. Log into `https://pokoin.com` in the same Chrome profile.
2. Open a Cardmarket product page.
3. Extension scrapes page title/context and resolves Pokoin candidates.
4. Extension requests token from the Pokoin auth bridge.
5. Extension posts to `/api/cardmarket-scrape-observation`.
6. Confirm a row appears in `marketplace_cm_scrape_observations`.
7. If `promoteVerifiedLink: true`, confirm the URL appears in
   `marketplace_cm_verified_links`.
8. Confirm `/api/cardmarket-redirect?id=<blueprint_id>&format=json` returns the
   promoted Cardmarket URL.
