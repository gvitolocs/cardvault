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

## Crypto swap / bridge

`workflows/swap_bridge-workflow.md`

`workflows/crypto-pkn-purchase-workflow.md`

## Codex in Cursor (local dev)

Use ChatGPT Plus/Pro Codex models inside Cursor via the local proxy:

`workflows/codex-cursor-proxy-workflow.md`

Quick start: `npm run codex:cursor-proxy` (Bun + `codex` auth). Auto-start at login: `npm run codex:cursor-proxy:install-launchagent`. Source: `github:wellbritto98/codex-cursor-proxy`.
