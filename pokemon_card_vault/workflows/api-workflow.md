# Pokoin API Workflow

Use this workflow when adding, removing, renaming, or materially changing an
endpoint under `api/*.js`.

## Route Sources

- `api/*.js` contains the endpoint implementations. Files that start with `_`
  are helper modules, not routes.
- `server/api-route-manifest.js` is the authoritative route inventory for the
  standalone Oracle API and for generated API docs.
- `server/oracle-api-server.js` serves the manifest routes on Oracle. Production
  `pokoin.com` normally proxies `/api/*` to `https://api.pokoin.com`.
- `vercel.json` keeps explicit local serverless rewrites for fallback mode and
  special static/proxy routes.
- `deploy-pokoin-web.sh` owns fallback Vercel packaging. In Oracle API mode it
  must not copy serverless functions; in fallback mode it must copy every routed
  endpoint and helper it needs.
- `scripts/check-oracle-api-server.js` validates manifest route resolution and
  handler module loading.
- `scripts/check-api-guardrails.js` statically enforces the production API
  discipline: manifest coverage, Oracle observability, shared helper usage for
  canonical URL/emoji/price/listing/comment logic, and cache headers on
  read-heavy marketplace routes.
- `scripts/check-api-route-tests.js` requires every public manifest route to
  have a direct `api/<route>.test.js` or an explicit reviewed baseline entry in
  `workflows/api-route-test-coverage.json`.
- `scripts/check-oracle-migrations.js` requires every
  `oracle-postgres/schema/*.sql` file to be listed in
  `oracle-postgres/schema-manifest.json` in apply order.
- `scripts/smoke-oracle-api-routes.js` performs safe local smoke requests across
  manifest routes.
- `api/pokoin-checkout-deploy-layout.test.js` guards critical route packaging,
  rewrites, helper path rewriting, and manifest coverage.
- `scripts/generate-api-docs.js` regenerates `docs/oracle-api-migration.md` from
  the manifest.

When a route changes, update all of the relevant sources in the same change. Do
not leave an API available in only one surface.

## API Inventory

Current manifest inventory: 78 manifest routes plus 4 static/proxy supply routes
in `vercel.json`.

### Marketplace Card, Search, Listing, And Price APIs (36)

- `GET /api/marketplace-home`: home snapshot and carousel sections.
- `GET /api/marketplace-cards`: searchable catalog/product rows.
- `GET /api/marketplace-card-versions`: card detail/version rows.
- `GET|HEAD /api/marketplace-card-url`: DB canonical card URL lookup.
- `GET /api/marketplace-card-seo`: bot/social metadata HTML for card pages.
- `GET|HEAD /api/marketplace-card-shortlink`: numeric root shortlink redirect.
- `GET|OPTIONS /api/marketplace-card-cheapest-price`: homepage-backed cheapest
  card price and CardTrader cache availability.
- `GET /api/marketplace-card-sales`: recent paid card sales from Firestore
  orders.
- `GET /api/marketplace-artist-cards`: artist profile/cards by illustrator.
- `GET /api/marketplace-artist-suggestions`: artist suggestions for pages/admin.
- `GET /api/marketplace-expansions`: expansion list/detail snapshots.
- `GET|POST /api/marketplace-expansion-symbols`: protected expansion symbol
  reads/updates.
- `POST /api/marketplace-search-candidates`: split/tokenized search rows.
- `POST|OPTIONS /api/marketplace-autocomplete`: ranked autocomplete suggestions.
- `GET|POST /api/searchbar-cards`: searchbar wrapper around autocomplete.
- `GET|POST|OPTIONS /api/searchbar-token-predict`: lightweight token prediction.
- `GET|POST /api/searchbar-cancel`: search cancellation marker.
- `POST|OPTIONS /api/extension-card-search`: browser-extension card search.
- `GET|POST|OPTIONS /api/deck-card-version-lookup`: decklist card version lookup.
- `GET /api/limitless-expansion-blueprints`: Limitless expansion to Pokoin
  blueprint mapping.
- `GET /api/marketplace-competitive`: Limitless competitive dashboard/detail.
- `GET /api/marketplace-hot-blueprints`: rolling hot blueprint analytics.
- `POST /api/marketplace-event`: bounded public marketplace event recording.
- `GET|POST|PATCH /api/marketplace-listings`: public listing reads plus
  authenticated seller writes.
- `POST /api/marketplace-cart`: cart add/remove analytics.
- `POST /api/marketplace-watchlist`: watchlist add/remove analytics.
- `GET|OPTIONS /api/marketplace-blueprint-price`: suggested listing/floor price
  for one blueprint/card ID.
- `GET|OPTIONS /api/cardtrader-blueprint-listings`: Oracle daily CardTrader
  listing snapshots.
- `GET|OPTIONS /api/cardtrader-live-listings`: live on-demand CardTrader listing
  metadata for card detail.
- `GET /api/cardmarket-redirect`: Cardmarket product/search redirect.
- `POST|OPTIONS /api/cardmarket-scrape-observation`: Cardmarket scrape review
  observations.
- `GET /api/marketplace-cardmarket-guess-review`: protected Cardmarket guess
  review.
- `GET|POST /api/marketplace-debug-refinement`: protected search refinement
  debug.
- `GET|POST /api/marketplace-debug-artists`: protected artist enrichment debug.
- `GET /api/marketplace-debug-events`: protected event analytics debug.
- `GET|POST /api/marketplace-debug-cardtrader-blueprints`: protected CardTrader
  import/debug queue.

### Assistant, Session, And Debug APIs (3)

- `POST /api/pokoin-assistant`: Pokontact assistant gateway with marketplace
  grounding and optional peer2 handoff.
- `GET|POST /api/user-current-page`: sanitized current internal page storage for
  assistant sessions.
- `GET|POST /api/flutter-debug-logs`: protected Flutter debug log write/read.

### Checkout, Orders, Cart, User, And Account APIs (23)

- `POST|OPTIONS /api/auth-login`: Firebase bearer-token validation.
- `POST /api/create-pkn-checkout-session`: Stripe Checkout session creation or
  reconciliation.
- `POST /api/stripe-webhook`: raw-body Stripe webhook for PKN balance credits.
- `POST /api/marketplace-orders`: paid marketplace order creation and seller
  notification retry.
- `POST /api/transfer-account-balance`: account balance transfer.
- `POST /api/top-up-account-balance`: native PKN top-up verification.
- `POST /api/request-pkn-withdraw`: withdraw site balance to native PKN address.
- `GET|POST /api/search-recipient-emails`: username search/ensure/update.
- `POST /api/register-email`: email/password pending signup.
- `POST /api/verify-email-signup`: pending signup token verification.
- `POST /api/signup-notification`: one-time signup notification email.
- `POST /api/upload-profile-picture`: authenticated R2 avatar upload.
- `POST /api/remove-profile-picture`: authenticated avatar removal.
- `POST /api/cache-google-profile-picture`: authenticated Google avatar caching.
- `POST /api/unlock-silver`: Silver status unlock.
- `POST /api/wallet-auth/nonce`: wallet sign-in nonce.
- `POST /api/wallet-auth/verify`: wallet signature verification/login.
- `POST /api/wallet-link`: link wallet to Firebase account.
- `POST /api/wallet-link/session`: create wallet-link session.
- `POST /api/wallet-link/complete`: complete wallet-link from signed payload.
- `GET|POST /api/crypto-pkn-purchase/:action`: crypto-to-PKN quote/request/status.
- `GET|POST /api/crypto-pkn-sale/:action`: PKN-to-crypto quote/request/status.
- `GET|POST /api/wpkn-exchange/:action`: native PKN/wPKN quote/request/status.

### CardTrader, Inventory, Sync, And Admin APIs (7)

- `POST|DELETE /api/cardtrader-connect`: connect/replace/disconnect seller
  CardTrader token.
- `GET /api/cardtrader-status`: safe seller integration status.
- `POST /api/cardtrader-disconnect`: disconnect seller integration.
- `POST /api/cardtrader-clean-listings`: deactivate CardTrader-linked seller
  listings.
- `POST /api/cardtrader-import-dry-run`: redacted seller import dry run.
- `GET|POST /api/cardtrader-daily-listings-refresh`: protected manual global
  listing snapshot diagnostic trigger. Scheduled ingestion belongs to Oracle.
- `GET /api/cardtrader-redirect`: CardTrader blueprint redirect.

### SEO, Shortlink, Health, Forum, Social, And Misc APIs (13)

- `GET /api/forum`: forum category/topic/post reads.
- `POST /api/forum-create-topic`: authenticated forum topic create.
- `POST /api/forum-create-post`: authenticated forum reply create.
- `POST /api/forum-upload-media`: authenticated forum media upload to R2.
- `POST|OPTIONS /api/earn-pkn`: sharding/deck review inquiry email.
- `POST /api/social-autopost`: protected social post dispatcher.
- `GET|POST /api/social-autopost/hot-card`: protected hot-card social posting.
- `POST /api/social-post-agent`: protected social copy generation.
- `POST|OPTIONS /api/trainingai-card-classify`: classifier proxy.
- `GET /healthz` and `GET /api/healthz`: Oracle API service health.
- `GET /api/__routes`: compact Oracle route index.
- `GET /api/total-supply` and `GET /api/circulating-supply`: external Pokoin
  status proxies from `vercel.json`.
- `GET /api/supply/total.txt` and `GET /api/supply/circulating.txt`: static text
  supply files under `web/api/supply`.

## Recent API Rules

- Canonical card URLs: user-facing card navigation, card tiles, assistant card
  links, and marketplace card suggestions must use `marketplace_card_urls` or
  `/api/marketplace-card-url`. Generated slugs are only for legacy URL repair,
  shortlink/SEO compatibility, or local fallback after DB resolution fails.
- Debug/session APIs: `/api/flutter-debug-logs` and `/api/user-current-page`
  must stay protected or sanitized. Debug logs require a debug token or
  authorized debug/admin Firebase bearer token; current-page writes accept only
  safe internal Pokoin paths or Pokoin URLs normalized to internal paths.
- Assistant/session identity: when a request includes an Authorization bearer
  token, the API must verify it and preserve the verified Firebase UID as the
  user's identity. Do not silently fall back to anonymous scope after token
  verification fails; expired/revoked/malformed tokens are authentication
  failures and should return a 401-style response or equivalent explicit auth
  error. The Flutter assistant client must request a fresh Firebase ID token for
  each authenticated assistant/current-page operation, or keep `_bearerToken`
  synchronized from `idTokenChanges()`, so long-lived tabs do not reuse expired
  tokens and trigger intermittent 500s.
- Pricing: marketplace homepage/catalog/extension prices use
  `/api/marketplace-card-cheapest-price` backed by
  `cheapest_homepage_cache_blueprint` or the legacy
  `cardtrader_blueprint_listing_cache` relation. Suggested listing price uses
  cached Oracle/CardTrader data through `/api/marketplace-blueprint-price`. Do
  not add live scraping or live CardTrader calls to these tile/suggestion paths.
- Card detail listings: `/api/cardtrader-live-listings` may fetch live
  CardTrader listing metadata for a specific card/blueprint, but public payloads
  must stay bounded and must not expose tokens, secrets, raw ingestion headers,
  or unbounded source blobs.
- Emoji fields: marketplace card/search/home/artist/expansion/version/deck APIs
  should return structured `cardIdentityEmojis` and `rarityVariantEmoji` through
  `_marketplace_card_emoji.withCardEmojiFields`. Do not reintroduce divergent
  one-off emoji normalization in individual endpoints.
- Seller comments: public listing APIs must filter promotional seller comments
  through `_seller_comment_filter`. Preserve useful condition notes, but hide
  store promos, external marketplace ads, and markup-heavy comments.
- Assistant grounding: `/api/pokoin-assistant` answers about marketplace prices,
  listings, popularity, and card links must use Oracle-backed APIs/tables and DB
  canonical paths. Do not answer from model memory or stale knowledge text.
- Search/debug auth: debug metadata and admin review endpoints must stay behind
  `_search_debug_auth` or equivalent Firebase role checks.

## Change Checklist

1. Add or update the endpoint implementation in `api/*.js`.
2. Add or update `server/api-route-manifest.js` with path, file, methods,
   purpose, auth, params, env, and service dependencies.
3. Add or update explicit `vercel.json` fallback rewrites for routable endpoints.
   Keep SEO/shortlink rewrites that pass query params in sync.
4. Add the endpoint to `deploy-pokoin-web.sh` fallback packaging and helper
   path-rewrite loops. Oracle API mode must still deploy static web only and
   proxy `/api/*`.
5. Add a direct `api/<route>.test.js`. Only use
   `workflows/api-route-test-coverage.json` for a reviewed legacy/baseline
   exception with a concrete reason and `coveredBy` checks.
6. Use shared helpers instead of local business logic:
   `marketplace-card-url`/`marketplace_card_urls` for canonical paths,
   `_marketplace_card_emoji` for emoji fields, `_pkn_checkout_pricing` or
   the CardTrader cache helpers for price conversion, `_seller_comment_filter`
   for public seller comments, and listing/cache helpers for marketplace
   availability. If a legacy route must keep duplicated logic, document the
   narrow exception in `scripts/check-api-guardrails.js`.
7. Public read-heavy marketplace routes must set `Cache-Control` or use a shared
   response helper that does. Mutating/auth/debug routes should normally use
   `no-store`.
8. New Oracle/Postgres schema files must be added to
   `oracle-postgres/schema-manifest.json` in sorted apply order. Duplicate
   numeric prefixes are not allowed unless explicitly documented there.
9. Update `scripts/smoke-oracle-api-routes.js` when the route needs a safe custom
   smoke request.
10. Update `api/pokoin-checkout-deploy-layout.test.js` for critical deploy
   contract coverage without creating broad brittle snapshots.
11. Run `npm run api:docs` when manifest metadata changes.
12. Update `docs/pokoin-api.md` or feature workflows when public behavior changes.

## Validation

Run the focused checks that match the change:

```bash
python3 -m json.tool vercel.json >/dev/null
bash -n deploy-pokoin-web.sh
node --test api/pokoin-checkout-deploy-layout.test.js
npm run api:check
npm run api:lint
npm run api:coverage
npm run api:migrations:check
npm run api:smoke
```

`npm run api:smoke` intentionally exercises safe error paths and can report
missing environment names. Do not print real secret values while investigating.

`npm run api:check` is the normal aggregate gate. It includes manifest/server
loading, static API guardrails, route test coverage baseline validation, and
Oracle schema manifest validation. `npm run api:smoke` stays separate because it
starts the local server and makes request-level smoke calls.
