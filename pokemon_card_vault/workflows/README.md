# Pokoin Agent Workflows

This folder is for future agents and operators. Use these workflows instead of
reconstructing commands from chat history.

## Project Shape

- `pokoin.com` is the canonical web origin for auth, wallet, profile, checkout,
  orders, marketplace, forum, docs, scan, and health pages.
- The web app is a Flutter web build deployed to Vercel. API functions under
  `api/*.js` must be copied into `build/web/api` during deployment.
- `explorer.pokoin.com` is an explorer/scan entry point. Protected account
  routes on subdomains redirect to `pokoin.com` in `vercel.json`.
- `rpc.pokoin.com` is the PokoinPoS node RPC domain and is not deployed from
  this Flutter project.
- Supabase stores the CardTrader Pokemon blueprint catalog in
  `public.cardtrader_pokemon_blueprints`.
- Marketplace pages should read lightweight Supabase projections before touching
  the heavy blueprint JSON:
  - `public.marketplace_cards` for home/search/catalog card rows.
  - `public.marketplace_card_events` for rolling marketplace analytics.
  - `public.marketplace_card_versions` for expansion-scoped navigation.
  - `public.cardtrader_pokemon_expansions` for imported expansion symbol CDN
    URLs from `ptcg-assets`.
- Firebase remains the production auth/profile/account store for the current
  marketplace app unless intentionally migrated. Active seller listings live in
  Firestore `card_listings`; the signal dashboard reads an aggregate stream from
  that collection.

## Secrets

- `.env.local` is intentionally gitignored. Read values from it, but never print
  tokens, service role keys, DB passwords, private keys, or webhook secrets.
- Required integration names used by these workflows:
  - `CARDTRADER_AUTH_TOKEN`
  - `SUPABASE_SECRET_ACCESS_KEY` or `SUPABASE_SECRET_ACCESS_TOKEN`
  - `SUPABASE_PROJECT_REF`
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SUPABASE_DB_URL`
  - `FIREBASE_CLI_PROJECT_ID` for Firebase CLI deploys

## Standard Workflows

1. Deploy web after app code changes:
   ```bash
   ./deploy-pokoin-web.sh
   ```
   `workflows/deploy-web.sh` is only a thin wrapper around this command. If a
   user asks whether a UI change is live, run a production deploy and verify
   `https://pokoin.com/main.dart.js`; pushing git or updating workflow docs does
   not update the live Flutter app.

2. Verify canonical account redirects:
   ```bash
   workflows/verify-domain-redirects.sh
   ```

3. Refresh CardTrader Pokemon blueprints locally:
   ```bash
   workflows/download-cardtrader-pokemon-blueprints.sh
   ```

4. Upload downloaded blueprints to Supabase:
   ```bash
   workflows/upload-cardtrader-blueprints-to-supabase.sh
   ```

5. Verify Supabase blueprint count:
   ```bash
   workflows/verify-supabase-cardtrader-blueprints.sh
   ```

6. Deploy Cloudflare redirect for `cardcaveau.com`:
   ```bash
   workflows/deploy-cardcaveau-cloudflare-redirect.sh
   ```

7. Update CardTrader blueprint images to Pokoin CDN URLs:
   ```bash
   workflows/update-cardtrader-cdn-images.sh
   ```

8. Deploy the `cdn.pokoin.com` proxy Worker route:
   ```bash
   workflows/deploy-pokoin-cdn-card-images.sh
   ```

9. Revise the card detail marketplace page:
   ```bash
   open workflows/card-market-page-workflow.md
   ```
   Also use this workflow for `/marketplace` home carousel changes. The home
   API returns section IDs and card payloads; the Flutter provider must merge the
   payload before resolving carousel IDs.

10. Maintain CardTrader-style search previews and Supabase fuzzy search:
   ```bash
   open workflows/cardtrader-search-preview-workflow.md
   ```

11. Import expansion symbols from `ptcg-assets`:
   ```bash
   DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   ```
   This writes `expansions/symbols/<expansion-name>.png` to R2 and upserts
   `public.cardtrader_pokemon_expansions`.

12. Refresh marketplace projections after a blueprint import or classifier
    change:
   ```bash
   supabase db push
   ```
   Then run the projection refresh functions from Supabase SQL editor or an
   authenticated script:
   ```sql
   select public.refresh_marketplace_cards_from_blueprints();
   select public.refresh_marketplace_card_versions();
   ```

## Operational Notes

- Do not use plain `vercel deploy` from the project root. It can publish an
  incomplete output. Always use `deploy-pokoin-web.sh` or
  `workflows/deploy-web.sh`.
- Do not confuse workflow/documentation commits with app deployment. Workflow
  commits help future agents, but user-visible marketplace/search fixes require
  `./deploy-pokoin-web.sh` after checks pass.
- Do not expose wallet/auth/profile on alternate origins. Account routes should
  canonicalize to `pokoin.com` to keep Firebase, Google auth, and MetaMask
  behavior consistent.
- Do not rely on paused Supabase projects. The old project
  `msngrrrihwudtnyjatlo` was inactive for over 90 days and unrecoverable through
  Supabase restore/backups.
- Before destructive Supabase actions, export or verify a backup. Prefer
  additive migrations and idempotent upserts.
- Cloudflare Worker routes require DNS records to be proxied. If a domain does
  not resolve, adding a Worker route is not enough.
- Card image matching is intentionally ID-based. R2 objects in
  `cardvault-images` use `<cardtrader_blueprint_id>_...` keys, and only matching
  blueprint IDs should update `image_url`.
- Card Reserve marketplace changes must follow
  `workflows/card-market-page-workflow.md` so `/card/:id`, seller listings,
  cart, checkout, and no-seller states stay connected to real Supabase/Firebase
  data instead of reverting to mock rows.
- Firebase CLI commands should use the local env project explicitly, for example
  `firebase deploy --only firestore:rules --project "$FIREBASE_CLI_PROJECT_ID"`,
  rather than changing global Firebase CLI state.
- Supabase migrations for CardTrader search should follow
  `workflows/cardtrader-search-preview-workflow.md`. Do not use the raw direct
  DB URL if it resolves to IPv6 and fails; relink with the DB password and push
  through Supabase CLI.
- Do not make `/card/:id` previous/next call Supabase on every arrow press. Load
  the ordered `marketplace_card_versions` rows for the current expansion once
  and compute previous/next locally while the user stays in that expansion.
- Do not make `/marketplace/search` depend only on `CardState.cards`. The home
  catalog is intentionally capped for performance; full search must query
  Supabase projections directly.
- Do not make `/marketplace` carousels depend only on the capped catalog either.
  Merge `/api/marketplace-home` snapshot cards into the provider state so
  Best sellers and Featured can resolve their section IDs.
- The marketplace top bar is shared in spirit across home, search, and card
  detail. Keep logo/search/navigation/wallet/cart behavior consistent when
  changing one surface.
- The homepage top bar should not duplicate primary actions. Keep `Shop` as the
  primary CTA and avoid repeating `Forum` or `Shop` inside adjacent controls.
- `/marketplace/signal` now shows real loaded catalog metrics and active
  Firestore listing metrics. Do not revert it to "analytics offline"; instead
  keep completed sales and 24h volume hidden until settled order events are
  wired.
