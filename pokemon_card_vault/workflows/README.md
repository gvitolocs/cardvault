# Pokoin Agent Workflows

This folder is for future agents and operators. Use these workflows instead of
reconstructing commands from chat history.

## Project Shape

- `pokoin.com` is the canonical web origin for auth, wallet, profile, checkout,
  orders, marketplace, forum, docs, scan, and health pages.
- The web app is a Flutter web build deployed to Vercel. Production `/api/*`
  traffic is proxied to the standalone Oracle API at `https://api.pokoin.com`;
  do not bundle Vercel serverless functions for normal production deploys.
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
  - `/api/marketplace-hot-blueprints` for rolling hot blueprint analytics.
  - `/api/marketplace-competitive` for Limitless-backed tournament standings
    and pairing snapshots.
  - `/api/marketplace-search-candidates` and `/api/marketplace-autocomplete`
    for tokenized search. In production, English searchbar/autocomplete
    candidate retrieval is Meilisearch-backed; non-English remains legacy.
- Oracle projection tables behind those APIs:
  - `public.marketplace_cards` for home/search/catalog card rows.
  - `public.marketplace_card_events` for rolling marketplace analytics.
  - `public.marketplace_hot_blueprints` for 1h/24h/7d hotness rollups used by
    the homepage and future search boosts.
  - `public.limitless_*` tables for competitive tournament/game/player,
    standings, pairings, decklist metadata, and Limitless sync runs. See
    `workflows/limitless-competitive-workflow.md`.
  - `public.marketplace_card_versions` for expansion-scoped navigation.
  - `public.marketplace_search_candidates` and token dimension tables for
    autocomplete/search.
  - `cheapest_homepage_cache_blueprint` as the canonical design concept for the
    cheapest eligible Zero + 1-Day Ready price per blueprint derived from the
    daily backend listings cache/import. Marketplace/homepage/catalog tile
    payloads read this projection for pricing; card detail seller rows keep
    using the live CardTrader parser. If production still exposes
    `public.cardtrader_blueprint_listing_cache`, treat it as the legacy physical
    table name until a migration renames it.
- Firebase remains the production auth/profile/account store for the current
  marketplace app unless intentionally migrated. Active seller listings live in
  Oracle Postgres `public.marketplace_user_listings`; listing writes and search
  debugger access are authenticated with Firebase ID tokens at the API boundary.

## Secrets

- `.env.local` is intentionally gitignored. Read values from it, but never print
  tokens, service role keys, DB passwords, private keys, or webhook secrets.
- This local checkout may keep its own Oracle access copy under `keys/` and
  `deploy/env/` so CardVault can operate without depending on the PokoinPoS
  working tree being open. These files are local-only and gitignored. It is okay
  for CardVault and PokoinPoS to both have copies because both projects operate
  Oracle services; keep values synchronized manually when rotating credentials.
- Operator scripts can also read a sibling PokoinPoS checkout through
  `POKOINPOS_ROOT` when that is more convenient. Default local value:
  `/Users/giuseppe/pokoinpos`.
- Required integration names used by these workflows:
  - `CARDTRADER_AUTH_TOKEN`
  - `SUPABASE_SECRET_ACCESS_KEY` or `SUPABASE_SECRET_ACCESS_TOKEN`
  - `SUPABASE_PROJECT_REF`
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SUPABASE_DB_URL`
  - `MARKETPLACE_DATABASE_URL`
  - `FIREBASE_CLI_PROJECT_ID` for Firebase CLI deploys

## Firebase CLI

- The local Firebase CLI is already logged in for this operator environment.
- Do not stop to ask for `firebase login` when a workflow needs Firebase CLI
  access. First run read-only checks such as:
  ```bash
  firebase projects:list
  firebase use "$FIREBASE_CLI_PROJECT_ID"
  ```
- Keep using Firebase Admin credentials from Vercel env for deployed API
  functions; local CLI login is only for operator commands and diagnostics.

## Standard Workflows

0. Check pending reports before site documentation or content updates:
   ```bash
   ls ../report/new
   ```
   Treat files in `../report/new` as pending source material for site docs,
   product pages, or operator notes. After incorporating a report, move the
   source file to `../report/old` so `../report/new` stays pending-only.

0a. Update common user action documentation when site behavior or Pokontact
    curated answers change:
   ```bash
   open docs/common-user-actions.md
   ```
   Keep this page aligned with common assistant answers for wallet, PKN/wPKN,
   Swap, marketplace listings, search, NFTs, nodes, live status, and bug reports.

0b. Use ChatGPT Plus/Pro Codex models inside Cursor via the local proxy:
   ```bash
   npm run codex:cursor-proxy
   npm run codex:cursor-proxy:install-launchagent
   ```
   Uses `github:wellbritto98/codex-cursor-proxy#main` via Bun. Requires Bun and
   `~/.codex/auth.json` from a prior `codex` login. Full setup:
   `workflows/codex-cursor-proxy-workflow.md`.

1. Deploy web after app code changes:
   ```bash
   ORACLE_API_BASE_URL=https://api.pokoin.com POKOIN_WEB_DEPLOY_TARGET=production ./deploy-pokoin-web.sh
   ```
   `workflows/deploy-web.sh` is only a thin wrapper around the deploy script. If a
   user asks whether a UI change is live, run a production deploy and verify
   `https://pokoin.com/main.dart.js`; pushing git or updating workflow docs does
   not update the live Flutter app. The script now treats post-deploy aliasing
   as mandatory: after `vercel deploy --prod`, it verifies the produced
   deployment URL, sets `pokoin.com`, `www.pokoin.com`, `wallet.pokoin.com`,
   `forum.pokoin.com`, `cards.pokoin.com`, `cardcaveau.pokoin.com`,
   `cardvault.pokoin.com`, and `explorer.pokoin.com`, then verifies those
   custom domains before returning success. The health checks include `/`,
   `/marketplace`, a representative marketplace card URL, and
   `/api/marketplace-home` JSON on canonical domains, and fail loudly on Vercel
   `404: NOT_FOUND` so aliases cannot silently point at an old broken
   deployment. Before deploying, confirm `https://api.pokoin.com/healthz` and
   `https://api.pokoin.com/marketplace` are healthy; if they are not, stop rather
   than falling back to Vercel serverless APIs.

1a. Production Oracle API facts:
   - `api.pokoin.com` is the first-class production API origin.
   - Peer3 SSH uses `ubuntu@141.147.62.244` and key files in
     `~/pokoinpos/keys/peer3`; never print private key contents.
   - If the local `peer3` SSH alias is unavailable, use explicit deploy env:
     `ORACLE_API_SSH_TARGET=ubuntu@141.147.62.244` and `ORACLE_API_SSH_KEY`
     pointing to the private key in `/Users/giuseppe/pokoinpos/keys` or the
     repo-documented Oracle keys folder. Do not assume bare `peer3` resolves.
   - The API runs on peer3 as Docker container `pokoin-oracle-api` on
     `127.0.0.1:18080`, behind Caddy container `pokoin-api-caddy` on 80/443.
   - Use Vercel serverless fallback only when explicitly requested as an
     emergency rollback.

1b. Maintain the API route inventory and deploy contract:
   ```bash
   open workflows/api-workflow.md
   npm run api:docs
   npm run api:check
   ```
   Use this workflow whenever adding, removing, or materially changing any
   `api/*.js` endpoint. The API route manifest is the authoritative inventory for
   the standalone Oracle API, while `vercel.json` and `deploy-pokoin-web.sh`
   remain the emergency Vercel serverless fallback contract. New endpoints are
   not deploy-ready until the manifest, rewrites, deploy packaging, route smoke
   scripts, generated docs, and deploy layout tests agree.

1c. Use Prisma as a secondary Oracle Postgres access layer:
   ```bash
   open workflows/prisma-oracle-workflow.md
   npm run prisma:validate
   npm run prisma:sync
   npm run prisma:smoke
   ```
   Prisma reads the same primary Oracle database via `MARKETPLACE_DATABASE_URL`
   by default, with optional `PRISMA_DATABASE_URL` override for future switch
   tests. Keep SQL migrations in `oracle-postgres/schema/` as the source of
   truth unless a Prisma migration plan is explicitly reviewed.

2. Verify canonical account redirects:
   ```bash
   workflows/verify-domain-redirects.sh
   ```

3. Refresh CardTrader Pokemon blueprints locally:
   ```bash
   workflows/download-cardtrader-pokemon-blueprints.sh
   ```

3a. Plan/import non-Pokemon CardTrader marketplaces only through isolated
    targets:
   ```bash
   open workflows/cardtrader-multigame-marketplaces-workflow.md
   node scripts/cardtrader-multigame-import.js --game=magic --discover-only
   ```
   Each non-Pokemon game must use its own database/schema target and CDN prefix.
   Do not import other games into the Pokemon Oracle tables or Pokemon Supabase
   name-index.

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

8a. Deploy the `trainingai.pokoin.com` read-only R2 sharing Worker:
   ```bash
   workflows/deploy-trainingai-cardvault-images.sh
   ```
   This endpoint shares the existing `cardvault-images` R2 bucket for image
   recognition training without exposing write credentials. It serves a styled
   Pokoin guide and import examples at `/`, a paginated JSON manifest at
   `/manifest.json` or `/images.json`, and card image objects at
   `/images/<object-key>`. It also serves the Oracle-derived classifier dataset
   manifest at `/blueprints/best-images.json`, with one best non-homepage image
   per CardTrader blueprint for incremental Colab embedding jobs. The
   `trainingai.pokoin.com` hostname should be configured as a Worker custom
   domain, not an R2 public bucket custom domain, so requests reach the Worker
   before any bucket access.
   The root route must return HTML; JSON belongs at the explicit manifest
   endpoints. The manifest page size defaults to 100 and can be raised up to
   1000 with `limit=...`; this is only a per-page size, not a total cap.
   Clients must follow `nextCursor` while `hasMore` is true to enumerate all
   shared card images. The Worker allows only `GET`, `HEAD`, and `OPTIONS`;
   includes CORS headers for download tooling; filters obvious
   non-card/user-media prefixes; and can be made token-protected by setting the
   Worker secret `TRAININGAI_ACCESS_TOKEN`. If that secret is absent, the route
   is intentionally public read-only.
   Regenerate and publish the best-blueprint manifest from Oracle/Postgres with:
   ```bash
   npm run trainingai:best-images -- --upload-r2
   workflows/deploy-trainingai-cardvault-images.sh
   curl -fsS https://trainingai.pokoin.com/blueprints/best-images.json \
     | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).count))"
   ```
   The generator reads `MARKETPLACE_DATABASE_URL` from `.env.local` by default,
   writes `data/trainingai/best-blueprint-images.json`, uploads it to
   `cardvault-images/manifests/best-blueprint-images.json` when `--upload-r2` is
   set, and never prints database or Cloudflare credentials.
   The same Worker also exposes `POST /api/classify` as the public TrainingAI
   classifier entrypoint. Prefer running the classifier on a lightweight Oracle
   VM with Colab-generated `pokemon.index`, `metadata.json`, and
   `card_paths.json` artifacts. Deploy the Oracle classifier with:
   ```bash
   TRAININGAI_ORACLE_SSH_TARGET=ubuntu@<oracle-vm-ip> \
   TRAININGAI_ORACLE_SSH_KEY=/path/to/private.key \
   workflows/deploy-trainingai-oracle-classifier.sh
   ```
   The service listens on the VM at `127.0.0.1:17860` by default and exposes
   `/health`, `/classify`, and `/classify/base64`. Put a small reverse proxy in
   front of it, for example `https://trainingai-api.pokoin.com`, then point the
   Worker at that base URL:
   ```bash
   wrangler secret put TRAININGAI_CLASSIFIER_URL --config wrangler.trainingai-cardvault-images.jsonc
   workflows/deploy-trainingai-cardvault-images.sh
   ```
   Hugging Face Spaces remains a fallback: `TRAININGAI_CLASSIFIER_URL` can also
   be set to `https://<user>-<space>.hf.space`. If the classifier backend is
   private, also set `TRAININGAI_HF_TOKEN`. The public endpoint accepts either
   multipart upload:
   ```bash
   curl -X POST https://trainingai.pokoin.com/api/classify \
     -F "image=@card.jpg" \
     -F "top_k=3"
   ```
   or JSON base64:
   ```bash
   curl -X POST https://trainingai.pokoin.com/api/classify \
     -H "Content-Type: application/json" \
     -d '{"imageBase64":"<base64>","topK":3}'
   ```
   Full Oracle classifier workflow: `workflows/trainingai-oracle-classifier-workflow.md`.
   The Worker also has an hourly cron trigger (`0 * * * *`) that sends a light
   `GET /health` keep-alive to `TRAININGAI_CLASSIFIER_URL` when configured. This
   is intended for a Hugging Face free-tier Space fallback and is intentionally
   hourly rather than aggressive.

   Cloudflare security for this hostname must keep the hostname-scoped legacy
   firewall bypass rule `Bypass legacy WAF for TrainingAI read-only image
   Worker` enabled for product `waf`. It matches only
   `(http.host eq "trainingai.pokoin.com")` and is needed because the managed
   WAF was blocking the originless Worker before Worker code executed. If
   Cloudflare returns `403` with body `Your request was blocked.` before the
   `x-cardvault-trainingai-worker` header appears, check that bypass rule and
   the Worker custom domain before changing global security settings. The
   read-only skip rule must also allow `GET/HEAD/OPTIONS` for
   `/blueprints/best-images.json`; the classifier API has a separate narrow
   skip rule for `POST/OPTIONS /api/classify`.

   Fetch all manifest pages:
   ```bash
   cursor=""
   while :; do
     url="https://trainingai.pokoin.com/manifest.json?limit=1000"
     if [ -n "$cursor" ]; then
       url="${url}&cursor=${cursor}"
     fi
     page="$(curl -fsS "$url")"
     printf '%s\n' "$page" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>JSON.parse(d).objects.forEach(o=>console.log(o.url)))"
     cursor="$(printf '%s\n' "$page" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const j=JSON.parse(d); if (j.nextCursor) console.log(j.nextCursor)})")"
     [ -n "$cursor" ] || break
   done
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

10a. Maintain Pokoin API auth:
   ```bash
   open workflows/pokoin-api-auth-workflow.md
   open docs/pokoin-api.md
   ```
   Pokoin API bearer tokens are Firebase ID tokens wrapped by the Flutter
   Pokoin API auth service. Keep protected Vercel APIs on `verifyBearerToken(req)`
   and route new Flutter calls through `PokoinApiClient`.
   Use this workflow for browser refresh boot issues, duplicate account/profile
   loads, profile-picture caching, cart cache boundaries, and logout/account
   switch cache clearing.

10b. Maintain social autoposting:
   ```bash
   open workflows/social-autoposter-workflow.md
   ```
   Use dry runs before any live Telegram or X post. Provider tokens stay in
   server-side environment variables only. Social copy uses a dedicated peer2
   `/social-post` route, not the Pokontact support `/chat` endpoint.

11. Maintain CardTrader-style search previews and Oracle fuzzy search:
   ```bash
   open workflows/cardtrader-search-preview-workflow.md
   ```
   This workflow documents the current production search path: Flutter debounces
   visible preview queries, Vercel calls Oracle Postgres tokenized search,
   structured multi-token queries use token intersection, variation tokens such
   as `v`, `ex`, `gx`, `vmax`, and `lv x` are weighted as structured dimensions,
   and Flutter renders the returned preview rows directly.

12. Map Pokoin/CardTrader blueprint IDs to Cardmarket products:
   ```bash
   open workflows/cardmarket-product-association-report.md
   open workflows/cardmarket-parsing-workflow.md
   ```
   This report records observed Cardmarket URL rules, including set-code product
   codes such as `CLSL02`, and should be updated whenever a new verified
   Cardmarket mapping is found.

13. Import expansion symbols from `ptcg-assets` and full logos from TCGdex
    metadata:
   ```bash
   DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
   node scripts/import-tcgdex-expansion-logos.js --limit=5
   node scripts/import-tcgdex-expansion-logos.js --apply --limit=all
   ```
   This writes `expansions/symbols/<expansion-name>.png` to R2 and upserts
   `public.cardtrader_pokemon_expansions`. The logo importer reads
   `marketplace_blueprint_tcg_metadata.set_logo_url`, writes
   `expansions/logos/<expansion-name>.<source-extension>`, and updates the
   expansion row's `logo_*` fields.

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
   Marketplace Postgres is peer4-primary with peer3 as the streaming fallback.
   After schema/import/refresh work, verify replication from the `pokoinpos`
   repo with `deploy/scripts/postgres-replication-status.sh`. Production Vercel
   env must include `MARKETPLACE_NAME_SEARCH_DATABASE_URL`,
   `MARKETPLACE_NAME_SEARCH_TIMEOUT_MS`, and
   `MARKETPLACE_NAME_SEARCH_CIRCUIT_MS` for split read search. This workflow
   also documents blueprint pricing tables, dimensional seller listing fields,
   targeted price summary refreshes, and `scripts/debug-marketplace-prices.js`.

15a. Refresh marketplace/homepage tile pricing from the daily listings cache:
   ```bash
   node scripts/oracle-marketplace-migrate.js schema
   node scripts/refresh-cardtrader-market-listings.js --env-file=/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env --dry-run --blueprint-id=316600 --max-blueprints=25 --max-products=250
   bash scripts/run-cardtrader-daily-market-refresh.sh
   ```
   The apply path upserts `public.cardtrader_market_listing_snapshots`, then
   derives `cheapest_homepage_cache_blueprint` for the touched blueprints from
   the daily backend listings cache/import. The normal wrapper is broad coverage
   for known Pokémon CardTrader blueprints; keep the explicit low limits only for
   dry-runs and diagnostics. This projection is canonical for
   marketplace/homepage/catalog tile pricing: it stores eligible listing
   count/quantity and, when safely available, the cheapest Zero + 1-Day Ready EUR
   price converted to PKN plus the 200 PKN reserve markup. If production still
   writes `public.cardtrader_blueprint_listing_cache`, that is the legacy physical
   table name for this projection until a migration renames it. It is not a live
   CardTrader call path and not a fallback behind old stock logic. Card
   detail/listing rows must keep using the live CardTrader parser for seller,
   condition, comment, shipping, and price detail.

15b. Roll out the competitive marketplace / Limitless data:
   ```bash
   open workflows/limitless-competitive-workflow.md
   node scripts/sync-limitless-competitive.js --dry-run --game=PTCG --max-tournaments=10
   node scripts/sync-limitless-competitive.js --apply --game=PTCG --max-tournaments=100
   ```
   Before expecting `/marketplace/competitive` to show data, apply the
   non-destructive Oracle/Postgres schema
   `oracle-postgres/schema/014_limitless_competitive.sql` to the writable
   primary, then sync Limitless data. Prefer dry-run and a small apply before a
   full or otherwise sensible public import. Public Limitless data can include
   games, tournaments, standings, and pairings where allowed; restricted
   decklist endpoints may require Limitless approval/API key and should be
   documented as a blocker instead of assumed. Do not deploy frontend-only for
   this feature unless an intentionally empty page is acceptable. Verify
   `https://api.pokoin.com/healthz`,
   `https://api.pokoin.com/api/marketplace-competitive`,
   `https://pokoin.com/marketplace/competitive`, and the trophy icon route.

16. Maintain the Pokontact assistant:
   ```bash
   open workflows/pokontact-assistant-workflow.md
   ```
   Use this when changing the Oracle peer2 Pokontact service, floating chatbot,
   `/api/pokoin-assistant` gateway, marketplace/card-price answers, assistant
   navigation actions, user-current-page/session page APIs, funny/cute assistant
   persona, or email forwarding to `pokoinpos@gmail.com`. Marketplace/card
   answers must be grounded in Oracle APIs/tables, direct card links must use
   `marketplace_card_urls` or `/api/marketplace-card-url`, and page-opening
   actions must use sanitized internal paths through structured client actions
   or the user-session current-page API.

16a. Maintain `news.pokoin.com` card highlight APIs in `hypemeter`:
   ```bash
   cd /Users/giuseppe/hypemeter
   open docs/pokoin-news-workflow.md
   ```
   The news site is the Vercel project `hypemeter`. Its Card Highlight JSON API
   lives at `/api/card-highlight`, and card images are proxied through
   `/api/card-highlight-image`. Do not add news/card-highlight endpoints to the
   CardVault Flutter app unless the API must be consumed by `pokoin.com`.

17. Configure domain email, Zoho Mail, and BIMI:
   ```bash
   open workflows/domain-email-workflow.md
   ```
   Use this when changing `@pokoin.com` mailbox delivery, Cloudflare Email
   Routing, Zoho MX/SPF/DKIM records, Resend transactional email, DMARC, or the
   BIMI logo record.

18. Maintain Pokoin icon/logo assets:
   ```bash
   open /Users/giuseppe/pokoinpos/src/logo/LOGO_INSTRUCTIONS.md
   ```
   The current approved icon is the 32x32 monster coin from
   `~/Downloads/Pokoin.svg`. Keep `web/pokoin.svg`, `web/pokoin-*.png`,
   favicons, `web/wpkn/logo.png`, the Hypemeter `public/pokoin*` files, and the
   PokoinPoS logo sources synchronized. Do not restore the older Pikachu-like
   artwork.

## Operational Notes

- nespc Cursor update + reboot is local-only on `192.168.178.25`. Use
  `workflows/nespc-cursor-reboot-workflow.md` and
  `workflows/nespc-update-cursor-and-reboot.sh`. Cloud agents cannot reach the
  LAN; do not treat Oracle peer reboots as substitutes for a nespc reboot
  request.
- Do not use plain `vercel deploy` from the project root. It can publish an
  incomplete output. Always use `deploy-pokoin-web.sh` or
  `workflows/deploy-web.sh`.
- Do not confuse workflow/documentation commits with app deployment. Workflow
  commits help future agents, but user-visible marketplace/search fixes require
  `./deploy-pokoin-web.sh` after checks pass, followed by custom-domain alias
  promotion when the returned deployment should become the live `pokoin.com`
  site.
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
- `trainingai.pokoin.com` is for read-only colleague access to CardVault card
  images only. Do not add write methods, R2 S3 credentials, private user media,
  wallet/auth/profile APIs, or broad unbounded bucket dumps to that Worker. The
  root path is a Pokoin-styled import guide; keep manifest JSON at
  `/manifest.json` or `/images.json`.
  Verify it with:
  ```bash
  curl -I https://trainingai.pokoin.com/
  curl -sS https://trainingai.pokoin.com/ | sed -n '1,8p'
  curl -sS https://trainingai.pokoin.com/manifest.json?limit=5
  curl -sS https://trainingai.pokoin.com/blueprints/best-images.json \
    | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).count))"
  curl -sS "https://trainingai.pokoin.com/manifest.json?limit=1000&cursor=<nextCursor>"
  curl -I https://trainingai.pokoin.com/images/<object-key>
  ```
- Card Reserve marketplace changes must follow
  `workflows/card-market-page-workflow.md` so `/card/:id`, seller listings,
  cart, checkout, and no-seller states stay connected to real Oracle/Firebase
  data instead of reverting to mock rows.
- Browser refresh should have one guarded auth bootstrap, then cached
  profile/balance/cart hydration, then live Firestore/API refresh. Do not add
  additional `authStateProvider` listeners that invalidate the same account
  providers during normal refresh.
- Cart and checkout are first-party Pokoin flows. Keep `/cart` and `/checkout`
  dark, premium, listing-aware, and PKN-first; do not revert to generic white
  ecommerce templates or client-only pending order creation for paid checkout.
- Profile pictures are immutable Cloudflare R2 URLs written by
  `/api/upload-profile-picture` and `/api/cache-google-profile-picture`. Flutter
  should render the stored `photoUrl` directly; do not append generic
  `updatedAt` query params that turn routine session touches into new avatar
  requests.
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
  `workflows/cardtrader-search-preview-workflow.md`: debounced warmup at 2
  characters, visible autocomplete at 3 characters, loaded-card ranking before
  remote enrichment, cached/popularity-ranked subpools, and local narrowing
  after that.
- Do not make the search page mutate `/marketplace/search?q=...` on every
  keystroke. The page results should update dynamically while the user types,
  but the route should remain static until an explicit submit/navigation.
- Single-token card names are first-class search intent. Keep `Lapras`, `Misty`,
  and similar card-name queries stronger than product/set noise unless the query
  explicitly asks for sealed products.
- Variation search work should update Oracle schema files and refresh
  projections. Exact `v` must remain a meaningful variation token, but do not
  let one-letter variation queries match every card from set/search text.
  Flutter guards and filters must keep standalone `v` alive even though it is a
  one-character query. Standalone `n` is also allowed because `N` is a real
  printed Trainer/card name; other one-character text searches should stay
  blocked.
- Do not make `/marketplace` carousels depend only on the capped catalog either.
  Merge `/api/marketplace-home` snapshot cards into the provider state so
  Best sellers and Featured can resolve their section IDs.
- Homepage Best sellers and Featured are real Oracle snapshot sections. Do not
  hardcode a specific expansion or rarity list in Flutter; use
  `sections.bestSellerIds` and `sections.featuredIds`, backed by
  `marketplace_hot_blueprints` and `get_marketplace_home_snapshot(...)`.
- Flutter marketplace events should send safe bounded metadata only: card
  identity dimensions and search context, never user identifiers or secrets.
- The marketplace top bar is shared in spirit across home, search, and card
  detail. Keep logo/search/navigation/wallet/cart behavior consistent when
  changing one surface.
- PokoinSwap UI changes live in the CardVault wallet surface
  (`lib/wallet/main.dart`) even though the AMM protocol is documented in the
  PokoinPoS repo. Keep the swap screen as a focused exchange interface:
  amount panels, token selectors, flip action, quote details, live pool reserve
  context, token-list discovery, and one primary swap action. The selector may
  show popular tokens from Ethereum/BNB Chain token lists and explorer-backed
  metadata, but execution must remain gated by `/chain/swap/pools`; tokens
  without a live `PKN <-> asset` pool are disabled as "no pool". The current
  native AMM supports two-way swaps between PKN and one pooled asset at a time,
  not direct asset-to-asset routes.
- The homepage top bar should not duplicate primary actions. Keep `Shop` as the
  primary CTA and avoid repeating `Forum` or `Shop` inside adjacent controls.
- `/marketplace/signal` now shows real loaded catalog metrics and active
  Firestore listing metrics. Do not revert it to "analytics offline"; instead
  keep completed sales and 24h volume hidden until settled order events are
  wired.
- `/forum` uses Firebase user identity, Supabase forum tables and Cloudflare R2
  media metadata. Keep writes behind Firebase-token-gated APIs instead of
  client-side Supabase writes.
- Pokontact assistant changes must follow
  `workflows/pokontact-assistant-workflow.md`.
  Keep the assistant cheerful and emoji-rich, keep card suggestions explicitly
  non-financial, and keep inquiry/bug forwarding admin-only through
  `POKOIN_ASSISTANT_EMAIL`. Do not answer marketplace price/popularity/card
  questions from model memory or stale text; query Oracle-backed APIs/tables and
  use DB canonical card paths. User-facing tile/card navigation must use DB
  canonical URLs; generated slug fallbacks are only for legacy direct URL repair.
- Debug, user-session, and current-page APIs must stay in sync across tests,
  deploy packaging, `vercel.json`, and `server/api-route-manifest.js` before
  they are considered deploy-ready.
