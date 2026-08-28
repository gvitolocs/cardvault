# Decision log (human backup)

Authoritative structured log: **Codevira** (`.codevira/decisions.jsonl`, `AGENTS.md`).

Record here only summaries that help humans; run `codevira list-decisions` for the full log.

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
