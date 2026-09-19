# Agent instructions (Pokoin / CardVault)

## Production deploy

- **Always** use `./deploy-pokoin-web.sh` for `pokoin.com` production.
- **Never** run bare `vercel --prod` from the repo root; it deploys API-only and
  breaks `/`, `/marketplace`, and all Flutter routes with Vercel `404 NOT_FOUND`.

## Incidents

If the site or `/marketplace` shows Vercel `404: NOT_FOUND`, follow:

`workflows/pokoin-vercel-404-recovery-workflow.md`

## Marketplace / cards

`workflows/card-market-page-workflow.md`

Our marketplace id is **our id** (`docs/marketplace-public-ids.md`):
`marketplace_cards.card_id` = old CardTrader blueprint × 2. We do not use `ct_id`
in URLs, API, Flutter, or image URLs. Never × 2 a catalog `card.id` or a Fast
Milo/TCGplayer id. pokoin-marketplace has 018 applied. Codevira D00000B.

## Multi-game CardTrader dump (One Piece / Riftbound)

Qwen: follow these two files. Do not print secrets.

- `workflows/cardtrader-multigame-marketplaces-workflow.md` (importer flags)
- `/home/nez/secrets/docs/CARDTRADER_MULTIGAME_DUMP.md` (hosts, WARP netns, 403)

Isolated DBs only (`pokoin_one_piece`, `pokoin_riftbound`). Never write into
Pokemon `public.cardtrader_pokemon_blueprints`. Frankfurt image hosts are
Cloudflare-403; use netns `igvpn` (nezopt) or `ctvpn` (peer1 WARP). Full
multithread (`--image-concurrency` 12–16, both games in parallel).

## Crypto swap / bridge

`workflows/swap_bridge-workflow.md`

`workflows/crypto-pkn-purchase-workflow.md`

## Codex in Cursor (local dev)

Use ChatGPT Plus/Pro Codex models inside Cursor via the local proxy:

`workflows/codex-cursor-proxy-workflow.md`

Quick start: `npm run codex:cursor-proxy` (Bun + `codex` auth). Auto-start at login: `npm run codex:cursor-proxy:install-launchagent`. Source: `github:wellbritto98/codex-cursor-proxy`.
