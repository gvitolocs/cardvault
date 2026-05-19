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
- Oracle Postgres stores the marketplace/catalog/search data. Supabase is kept
  for forum tables only.
- Trainer-owner metadata is structured separately from free-text card names:
  `marketplace_cards.trainer_name`, `marketplace_card_versions.trainer_name`,
  and `public.marketplace_trainers` support owner searches such as
  `garchomp di camilla` without broad multilingual fuzzy matching.
- Marketplace pages should read lightweight Oracle-backed Vercel APIs:
  - `/api/marketplace-home` for home snapshot and carousel payloads.
  - `/api/marketplace-cards` for catalog/product rows.
  - `/api/marketplace-card-versions` for expansion-scoped navigation.
  - `/api/marketplace-search-candidates` and `/api/marketplace-autocomplete`
    for tokenized search.
- Oracle projection tables behind those APIs:
  - `public.marketplace_cards` for home/search/catalog card rows.
  - `public.marketplace_card_events` for rolling marketplace analytics.
  - `public.marketplace_card_versions` for expansion-scoped navigation.
  - `public.marketplace_search_candidates` and token dimension tables for
    autocomplete/search.
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
  - `MARKETPLACE_DATABASE_URL`
  - `FIREBASE_CLI_PROJECT_ID` for Firebase CLI deploys

## Standard Workflows

0. Check pending reports before site documentation or content updates:
   ```bash
   ls ../report/new
   ```
   Treat files in `../report/new` as pending source material for site docs,
   product pages, or operator notes. After incorporating a report, move the
   source file to `../report/old` so `../report/new` stays pending-only.

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

4. Upload downloaded blueprints to Oracle marketplace Postgres:
   ```bash
   node scripts/oracle-marketplace-migrate.js all
   ```

5. Verify Oracle marketplace search:
   ```bash
   node scripts/oracle-marketplace-migrate.js verify
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

10. Revise the forum:
   ```bash
   open workflows/forum-workflow.md
   ```
   Use this when changing `/forum`, Supabase forum tables, Firebase-authenticated
   forum APIs, or Cloudflare R2 forum media uploads.

11. Maintain CardTrader-style search previews and Oracle fuzzy search:
   ```bash
   open workflows/cardtrader-search-preview-workflow.md
   ```
   This workflow documents the current production search path: Vercel calls
   Oracle Postgres tokenized search, Flutter caches a broad pool, continued
   typing narrows locally, variation tokens such as `v`, `ex`, `gx`, `vmax`,
   and `lv x` are weighted as structured dimensions, and the UI highlights both
   full terms and ordered single-character matches.

12. Map Pokoin/CardTrader blueprint IDs to Cardmarket products:
   ```bash
   open workflows/cardmarket-product-association-report.md
   open workflows/cardmarket-parsing-workflow.md
   ```
   This report records observed Cardmarket URL rules, including set-code product
   codes such as `CLSL02`, and should be updated whenever a new verified
   Cardmarket mapping is found.

13. Import expansion symbols from `ptcg-assets`:
   ```bash
   DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   ```
   This writes `expansions/symbols/<expansion-name>.png` to R2 and upserts
   `public.cardtrader_pokemon_expansions`.

14. Refresh Oracle marketplace projections after a blueprint import or
    classifier change:
   ```bash
   node scripts/oracle-marketplace-migrate.js schema
   node scripts/oracle-marketplace-migrate.js refresh
   ```

15. Operate Oracle marketplace Postgres and guarded Supabase cleanup:
   ```bash
   open workflows/oracle-marketplace-postgres-workflow.md
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
- Before destructive Supabase actions, export or verify a backup. Marketplace
  cleanup must use `scripts/supabase-cleanup-marketplace.js`; never manually
  drop tables from chat memory.
- Cloudflare Worker routes require DNS records to be proxied. If a domain does
  not resolve, adding a Worker route is not enough.
- Card image matching is intentionally ID-based. R2 objects in
  `cardvault-images` use `<cardtrader_blueprint_id>_...` keys, and only matching
  blueprint IDs should update `image_url`.
- Card Reserve marketplace changes must follow
  `workflows/card-market-page-workflow.md` so `/card/:id`, seller listings,
  cart, checkout, and no-seller states stay connected to real Oracle/Firebase
  data instead of reverting to mock rows.
- Firebase CLI commands should use the local env project explicitly, for example
  `firebase deploy --only firestore:rules --project "$FIREBASE_CLI_PROJECT_ID"`,
  rather than changing global Firebase CLI state.
- Oracle schema/search migrations should follow
  `workflows/oracle-marketplace-postgres-workflow.md` and
  `workflows/cardtrader-search-preview-workflow.md`.
- Do not make `/card/:id` previous/next call the database on every arrow press. Load
  the ordered `marketplace_card_versions` rows for the current expansion once
  and compute previous/next locally while the user stays in that expansion.
- Do not make `/marketplace/search` depend only on `CardState.cards`. The home
  catalog is intentionally capped for performance; full search must query
  Oracle-backed marketplace APIs directly.
- New search work should preserve the candidate-pool model documented in
  `workflows/cardtrader-search-preview-workflow.md`: remote indexed search at 3
  characters, cached/popularity-ranked subpools, and local narrowing after that.
- Variation search work should update Oracle schema files and refresh
  projections. Exact `v` must remain a meaningful variation token, but do not
  let one-letter variation queries match every card from set/search text.
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
- `/forum` uses Firebase user identity, Supabase forum tables and Cloudflare R2
  media metadata. Keep writes behind Firebase-token-gated APIs instead of
  client-side Supabase writes.
