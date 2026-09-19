# Decision log (human backup)

Authoritative structured log: **Codevira** (`.codevira/decisions.jsonl`, `AGENTS.md`).

Record here only summaries that help humans; run `codevira list-decisions` for the full log.


## 2026-09-01 — Do not paint DP silver headers as yellow ears

- **Decision**: Light interior that is not yellow hue is the name/HP bar, not a die-cut ear. `fillInsideDieCutEars` must stop at measured T. Cropped yellow `paintStraightFrame` is weld-only.
- **Rationale**: Gible/Bidoof nicks were `(254,230,78)` on silver that matches official `(182,172,163)`.
- **Do not revert**: Keep Gyarados pad-0 AABB filling blue jags in the frame band.

## 2026-08-31 — Gold foil is not a yellow frame

- **Decision**: If ≥40% of sampled opaque pixels are yellow hue, the raster is gold foil (hyper-rare), not a printed yellow rim. Die-cut only. Always encode from the pokemontcg.io PNG; leftover keys often omit `hyper-rare`.
- **Rationale**: Mega Lucario ex 188 and Mega Gardevoir ex 187 were welded to `(255,211,0)`. Wizards yellow rims are ~15–20% yellow pixels (Gyarados still welds).
- **Do not revert**: Codevira lock on `isGoldFoilRaster`. Do not treat gold HR as D00000I AABB yellow.

## 2026-08-29 — Our id only (no public ct_id)

- **Decision**: Pokoin marketplace uses one id: `card_id` (old CardTrader blueprint × 2). We do not use `ct_id` in URLs, API, Flutter, or image URLs.
- **Rationale**: Giuseppe: our id is the doubled number; memories that kept CDN/internal ids on CardTrader were confusing after 018.
- **Do not revert**: Codevira CardVault D00000B (supersedes D00000A). BattleScan D00000E (supersedes D000009). Do not rewrite public/image URLs back to CardTrader numbers.

## 2026-05-27 — Dual memory for Cursor

- **Decision**: Use Honcho Cloud workspace `pokoin-cursor` for conversational coding memory; keep Codevira for structured decisions.
- **Rationale**: Same Honcho account as Hermes, but isolated workspace so personal/operator context does not leak into Pokoin.
- **Do not revert**: Mixing `hermes-peer1` workspace into Pokoin Cursor work.

## 2026-05-27 — Secrets layout (Codevira D000001–D000004)

- **Decision**: Document per-project secret locations — Honcho in `.env.honcho.local`, Hermes/Flareon in `private/flareon/`, Pokoin app in `pokemon_card_vault/.env.local`, handoff file for Flareon summary only.
- **Rationale**: Agents must know paths without reading or committing values.
- **Do not revert**: Storing payment/auth secrets in Flareon operator env or pasting keys into Codevira/Honcho.

## 2026-05-27 — Flareon awareness without code dumps

- **Decision**: Maintain `memory/flareon-handoff.md` and sync to peer1 for Flareon; do not store full Pokoin codebase in Hermes memory.
- **Rationale**: Flareon should know project focus and Cursor conversation themes; detail stays in `pokoin-cursor` + Codevira.
- **Do not revert**: Pasting large files into `hermes-peer1` or skipping handoff sync when focus changes materially.

## 2026-05-28 — Prisma as secondary Oracle access layer

- **Decision**: Initialize Prisma in `pokemon_card_vault/` against the existing
  Oracle Postgres `pokoin_marketplace` database. Prisma uses
  `MARKETPLACE_DATABASE_URL` by default and optional `PRISMA_DATABASE_URL` for
  future switch tests.
- **Rationale**: Gives agents a typed/introspected database access path without
  replacing the current production API `pg` helpers or SQL migration flow.
- **Do not revert**: Do not run Prisma migrations against production Oracle or
  replace canonical SQL under `oracle-postgres/schema/` without an explicit
  reviewed migration plan.

## 2026-05-28 — English production search uses Meilisearch

- **Decision**: Keep Meilisearch enabled only for English searchbar/autocomplete
  queries. `api.pokoin.com` uses Meili as candidate retrieval, then Oracle
  hydrates/ranks authoritative rows; `it` and other languages remain legacy.
- **Rationale**: The old split/legacy path could return empty first-character
  pools and multi-second `pika+` latency. The production path now stays on
  `meili_en_candidates` for English and keeps a caller-owned fallback if Meili
  is empty/unavailable.
- **Do not revert**: Do not point the Docker API at peer3 loopback
  `127.0.0.1:27700`; the API container must use the Docker-bridge Meili
  endpoint provided by `pokoin-meili-peer-tunnel.service`.

## Template

```markdown
### YYYY-MM-DD — Title
- **Decision**:
- **Rationale**:
- **Do not revert** (if locked):
```

## 2026-09-11 — Pi API origin, Oracle CardTrader dump primary

- **Decision**: Public `api.pokoin.com` / `cdn.pokoin.com` stay on pi-home. Oracle `pokoin-marketplace` is the CardTrader dump / Postgres write primary. Pi Postgres is a streaming replica the API reads at `127.0.0.1:5432`. English Meili lives with the Pi API. Never dump-write or migrate on the replica. Never leak `ECONNREFUSED` / `127.0.0.1:5432` to the SPA (503 WorkingOnIt + nezopt uptime mail).
- **Rationale**: Giuseppe 2026-09-11: APIs are from the Pi; Oracle is just for the CardTrader dump. The 2026-09-06 “Pi write primary / Oracle streaming backup” memory is wrong.
- **Do not revert**: Do not promote a second primary from `/srv/pokoin/postgres.promoted-primary-backup` while Oracle is already writable.

## 2026-08-29 — API-first React contract

Public marketplace on pokoin.com migrates to React/Next.js against `https://api.pokoin.com`. Flutter remains Android/iOS. Business rules stay in `api/*.js` (Oracle), not Vercel serverless or the browser. Canonical write-up: `pokemon_card_vault/docs/react-api-architecture.md`.

## 2026-08-30 — React page BFFs, not Flutter web patches

- **Decision**: Public pokoin.com strangler-replaces to Next.js against new page BFFs. Do not keep investing in Flutter web Hero/CanvasKit.
- **Rationale**: Live Flutter site is laggy, Hero is disabled on web, tiles stretch 180px `/previews/` because `homepageImageUrl` copies preview JPEGs.
- **Do not revert**: API-first; no Vercel serverless; public id = CT×2; leftover R2 keys stay `ct_id_`; public image URLs use our id (Worker maps).

