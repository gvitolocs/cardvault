# Cursor → Codex Handoff (cardvault)

## 1) What this project is
- Pokoin is a PoS + EVM-compatible ecosystem: native PKN transfer rails, public RPC/explorer surfaces, and wPKN interoperability on BSC for liquidity/bridge flows.
- `cardvault/` is the operator/coding workspace; the main app product is `pokemon_card_vault/`.
- CardVault is now the flagship consumer layer for Pokoin: Pokemon card marketplace UX, card analytics/search, competitive (Limitless-style) data views, pricing pipelines (CardTrader/native cache), wallet/scan/explorer pages, and payment/sharding related flows.
- Current production shape:
  - Web/app entrypoints on `https://pokoin.com` (+ subdomain aliases such as `explorer.pokoin.com`)
  - Oracle-hosted API origin on `https://api.pokoin.com` (not serverless-first)

## 2) Current architecture and important folders
- `pokemon_card_vault/`
  - `lib/` Flutter UI/app logic
  - `api/` Node API handlers (proxied from web in normal prod flow)
  - `server/` Oracle API server wiring
  - `oracle-postgres/` schema and DB rollout docs
  - `deploy-pokoin-web.sh` canonical production web deploy script
  - `workflows/` operational playbooks
- `memory/`
  - `current-state.md`, `architecture.md`, `decisions.md` human-readable project memory
- `.codevira/` + root `AGENTS.md`
  - structured project decisions and do-not-revert constraints

## 3) Current active work / priorities
- Ongoing Pokoin marketplace + Oracle API evolution in `pokemon_card_vault/` (large in-progress working tree).
- Preserve production architecture: frontend on Vercel, APIs on Oracle (`api.pokoin.com`), avoid accidental serverless fallback.
- Local developer setup work in progress around Codex/Cursor proxy startup and reliability.

## 4) Important locked decisions and do-not-revert rules
From Codevira (`D000001`–`D000004`, all locked):
- Keep memory layers separated by purpose (Cursor coding memory vs operator/bot memory).
- Keep secrets in dedicated secret stores; do not move/copy secrets into shared memory/docs/logs.
- Flareon/Pokoin cross-awareness should be summary-based, not full code/log duplication.
- Pokoin runtime secrets remain in app/runtime secret locations, not mixed with unrelated operator envs.

Also from project rules:
- Use production-safe deploy workflow (`deploy-pokoin-web.sh`), not ad-hoc deploy commands.
- Treat APIs as first-class infra (`api.pokoin.com` health/routes checked before frontend prod deploy).

## 5) Deployment/runtime notes
- Canonical web deploy command:
  - `ORACLE_API_BASE_URL=https://api.pokoin.com POKOIN_WEB_DEPLOY_TARGET=production ./deploy-pokoin-web.sh`
- Oracle API runtime is expected on peer3 behind Caddy (per workflows/rules).
- `explorer.pokoin.com` is an entrypoint; protected/account flows should remain canonicalized to `pokoin.com`.

## 6) Known gotchas
- Working tree is very dirty with many tracked/untracked files; avoid broad commits by accident.
- Existing project memory references a Honcho workspace `pokoin-cursor`, but current Honcho MCP listing does not show it.
- Honcho currently exposes only:
  - `hermes-peer1`
  - `poko-peer1`
- Current `inspect_workspace` resolves to `hermes-peer1`; search results are mostly ops/infrastructure context, not focused Pokoin coding memory.
- If session memory seems mismatched, verify Honcho workspace wiring before relying on retrieved context.

## 7) What Codex should do first when resuming work
1. Read:
   - `AGENTS.md`
   - `memory/current-state.md`
   - `memory/architecture.md`
   - `memory/decisions.md`
   - `pokemon_card_vault/workflows/README.md`
2. Check repo state:
   - `git status -sb` at `cardvault/` and scope target changes carefully.
3. Confirm runtime targets before deploy work:
   - API health (`api.pokoin.com`)
   - web deploy path (`deploy-pokoin-web.sh`)
4. For memory continuity:
   - Use Codevira decisions as authoritative for locked constraints.
   - Use Honcho carefully until workspace mapping is corrected.

## 8) Honcho memory summary relevant to this repo
- Requested workspace (`pokoin-cursor`) is **not present** in currently accessible Honcho workspaces.
- Accessible workspaces: `hermes-peer1`, `poko-peer1`.
- Current active inspected workspace: `hermes-peer1`.
- Relevant-memory quality for this repo: **low/indirect** (mostly operator/infra chatter; limited Pokoin coding continuity).
- Action for follow-up: verify Honcho workspace configuration expected by `docs/cursor-memory-setup.md` (it expects `pokoin-cursor` for Cursor coding memory).

## 9) Cross-project workflows index (for Honcho/Codex organization)
Scanned from your workspace roots; this is the actionable map.

- **`cardvault/pokemon_card_vault`** (primary, 51 files)
  - Core entrypoint: `cardvault/pokemon_card_vault/workflows/README.md`
  - Key operational workflows:
    - `.../api-workflow.md`
    - `.../oracle-marketplace-postgres-workflow.md`
    - `.../card-market-page-workflow.md`
    - `.../pokoin-vercel-404-recovery-workflow.md`
    - `.../limitless-competitive-workflow.md`
    - `.../meilisearch-peer-workflow.md`
    - `.../codex-cursor-proxy-workflow.md`
    - plus `workflows/reports/*.md` historical report workflows

- **`cardvault/pokemon_card_vault-home-availability-deploy/pokemon_card_vault`** (snapshot/parallel tree, 46 files)
  - Entry: `.../workflows/README.md`
  - Mostly mirrors main Pokoin workflow set with historical `reports/*.md`.

- **`drafttool`** (1 file)
  - `drafttool/workflows/README.md`

- **`Hermes`** (1 file)
  - `Hermes/workflows/README.md`

- **Requested but no `workflows/*.md` folder found**
  - `pokoinpos`
  - `pokemon-card-extension`
  - `SCAN_CARD_IA`

Recommendation for next agent: start from each project's `workflows/README.md`, then branch into domain-specific workflow files.
