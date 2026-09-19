# Pokoin app collaborator guide

For Codex / Cursor coworkers building the **app** (Flutter mobile, React web, APIs).
This pack is a downloadable snapshot. Live truth still lives in the git repo + Pi API.

## 60-second topology

```text
App (Flutter Android/iOS)  ──┐
React web (pokoin.com)     ──┼── /api/* ──► https://api.pokoin.com  (Docker on **pi-home**)
Chrome extension           ──┘                    │
                                                  ├─ Meili 127.0.0.1:7700 (on Pi)
                                                  ├─ Valkey / Redis (on Pi)
                                                  └─ Postgres replica 127.0.0.1:5432 (on Pi)
                                                         ▲ streaming replica
                                                         │
                              pokoin-marketplace Oracle ─┘  primary dump DB :5432
                              (CardTrader import / migrations write HERE)

cdn.pokoin.com  → Cloudflare → card images (R2 / Pi tunnel)
rpc.pokoin.com  → Oracle peer1 (chain / this Codex pack download)
```

| Host | Role | You usually… |
| --- | --- | --- |
| `https://pokoin.com` | Public web (React) + Flutter mobile clients talk here for `/api` rewrite | Build UI |
| `https://api.pokoin.com` | **Production API on Raspberry Pi** (Cloudflare tunnel) | Call / debug APIs |
| `pokoin-marketplace` (`130.61.251.250`) | Postgres **primary** (CardTrader dump) | Migrations, dump jobs — not app UI |
| `cdn.pokoin.com` | Card images | Use `imageUrl` / `gridImageUrl` from API JSON |
| `rpc.pokoin.com` | PokoinPoS RPC + this docs pack | Chain / download docs |

**Locked:** public API stays on **pi-home**. Do not move production API to Oracle peer1 or revive dead peer3.

## What the product can do (surfaces)

| Surface | URL / entry | Notes |
| --- | --- | --- |
| Marketplace browse / search / card desk | `pokoin.com` | React page BFFs — see `docs/react-page-apis.md` |
| Auth / wallet / profile / checkout / orders | `pokoin.com` (canonical) | Firebase bearer → API |
| Scan Connect (desk ↔ phone) | `pokoin.com/scan`, `dashboard…/scan`, `/connect` | Pairing PIN + stream APIs |
| Competitive / Limitless views | marketplace competitive routes | Needs Limitless data in Postgres |
| Chrome extension overlays | Cardmarket / CardTrader pages | Same `api.pokoin.com` |
| Wallet / PKN / wPKN | `pokoin.com/wallet` | MetaMask + RPC |
| Explorer / RPC | `explorer.pokoin.com`, `rpc.pokoin.com` | Chain ops, not marketplace UI |
| CDN images | `cdn.pokoin.com` | Prefer URLs from API payloads |

User-facing flows (wallet, MetaMask, scan language): `docs/common-user-actions.md`.

## App ↔ API contract (start here)

1. **Base URL:** `https://api.pokoin.com` (handlers under `/api/...`).
2. **Auth:** Firebase ID token as `Authorization: Bearer <token>` on protected routes. Details: `docs/pokoin-api.md`.
3. **Public card id:** our id = old CardTrader blueprint × 2. Never invent CDN names. `docs/marketplace-public-ids.md`.
4. **React web** must use **page BFFs**, not Flutter snapshot endpoints:
   - `GET /api/marketplace-home-page`
   - `GET /api/marketplace-search-page`
   - `GET /api/marketplace-card-page`
   - `GET /api/marketplace-expansion-page`
   - Live machine contract: `GET https://api.pokoin.com/api/__contract`
5. **Flutter mobile** keeps older granular APIs (`marketplace-cards`, `marketplace-listings`, `marketplace-card-versions`, …).
6. **Health:** `GET https://api.pokoin.com/healthz` (Postgres + Valkey + Meili + CDN). Pipeline failures → HTTP 503 + SPA “Working on it”.

Full human API book: `docs/pokoin-api.md`  
Route catalog (machine): `docs/api-route-catalog.json`  
React architecture: `docs/react-api-architecture.md`  
Page BFFs: `docs/react-page-apis.md`

## What you can call / change (by role)

### App engineer (typical coworker)

- Build Flutter screens / React pages against documented APIs
- Add client calls only for routes that already exist in `api/` + `__contract`
- Use search/autocomplete (`marketplace-suggest`, `marketplace-autocomplete`, `marketplace-search-*`)
- Use listings, orders, portfolio, watchlist, chat, scan APIs as documented
- Point local/dev at `api.pokoin.com` or `npm run api:server` → `127.0.0.1:18080` when running API locally
- **Do not** add Vercel serverless API functions for production
- **Do not** invent prices or listing data in the client — always from API

### API / Pi engineer

- Handlers live in `pokemon_card_vault/api/*.js`, served from Pi Docker
- Deploy / ops: `workflows/api-workflow.md`, `workflows/meilisearch-peer-workflow.md`
- Auth wiring: `workflows/pokoin-api-auth-workflow.md`
- Postgres: primary on `pokoin-marketplace`; Pi reads replica — `workflows/oracle-marketplace-postgres-workflow.md`

### Data / catalog

- CardTrader daily listings import writes **primary** Oracle DB only
- Public ids / hops: `docs/marketplace-public-ids.md`
- Image sanitize / CDN: `docs/marketplace-card-image-pipeline.md`, `docs/card-image-sanitize.md`
- Search ranking: `docs/marketplace-search-ranking.md`

### Payments / wallet (careful)

- Stripe / PKN checkout: `workflows/stripe-pokoin-checkout-workflow.md`, `workflows/crypto-pkn-purchase-workflow.md`
- Never print secrets; see repo `memory/secrets-workflow.md` (paths only)

## Smoke checks (no secrets)

```bash
curl -fsS https://api.pokoin.com/healthz
curl -fsS 'https://api.pokoin.com/api/marketplace-suggest?q=pika' | head -c 400
curl -fsS https://api.pokoin.com/api/__contract | head -c 400
curl -fsS https://pokoin.com/ | head -c 200
curl -fsS https://rpc.pokoin.com/health
```

## How to use this pack with Codex

1. Unzip next to the app checkout (or open as a second root).
2. Tell Codex: *Read `AGENTS.md`, then `APP_COLLABORATOR.md`, then the doc under `docs/` that matches the task.*
3. For Obsidian-style knowledge notes: `playbook/obsidian-documentation.md` + `vault/Pokoin/` (read-only snapshot). Live vault remains on Pi.
4. Prefer **repo** `docs/` + `workflows/` for “how to run”; use Obsidian vault for how claims connect.

## Pack layout

| Path | Contents |
| --- | --- |
| `AGENTS.md` | Short rules for Codex |
| `APP_COLLABORATOR.md` | This file |
| `docs/` | API + React + ids + user actions + route catalog |
| `workflows/` | Operator playbooks (API, Meili, Postgres, auth, deploy) |
| `memory/` | Architecture / current-state / Obsidian playbook |
| `playbook/` | Obsidian templates |
| `vault/Pokoin/` | Obsidian snapshot (hub, Permanent, Events, MOCs) |

## Out of scope in this zip

- Secrets / `.env` / SSH keys
- Full Flutter/`lib` or `api` source trees (use git)
- Writing to the live Pi Obsidian vault (needs `pi-cursor` SSH)

Republish after big doc changes: `cardvault/scripts/publish-codex-obsidian-pack.sh`
