# Pokoin/CardVault Agent Workflows

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
- Firebase remains the production auth/profile/account store for the current
  marketplace app unless intentionally migrated.

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

## Standard Workflows

1. Deploy web:
   ```bash
   workflows/deploy-web.sh
   ```

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

## Operational Notes

- Do not use plain `vercel deploy` from the project root. It can publish an
  incomplete output. Always use `deploy-pokoin-web.sh` or
  `workflows/deploy-web.sh`.
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
- Card detail page changes should follow `workflows/card-market-page-workflow.md`
  so CardTrader-style collectible listings and DEX-style market panels stay
  consistent.
