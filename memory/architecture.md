# Architecture (high level)

## Repositories

- `cardvault/` — Cursor workspace root (Codevira + Honcho MCP + memory docs)
- `pokemon_card_vault/` — Flutter web app, Vercel deploy scripts, Oracle API code, Prisma setup
- `oracle-postgres/` — Postgres schema/migrations for Oracle API (when present in tree)

## Runtime topology

- **Web**: Vercel-hosted Pokoin frontend; `/api/*` proxied to Oracle API in normal production.
- **API**: Docker on Oracle peer3 (`pokoin-oracle-api` + Caddy TLS), not Vercel serverless by default.
- **Search**: English autocomplete/searchbar first-stage retrieval uses
  Meilisearch on the dedicated peer, reached from peer3 through
  `pokoin-meili-peer-tunnel.service`; Oracle still hydrates and ranks the final
  rows. Non-English traffic stays on legacy Oracle/Supabase search.
- **Data**: Oracle Postgres stores marketplace/catalog/search data and is read
  through `MARKETPLACE_DATABASE_URL`. Supabase remains for forum/auth-adjacent
  tables and derived optional indexes only.
- **Prisma**: `pokemon_card_vault/prisma/schema.prisma` is an introspected view
  of Oracle `pokoin_marketplace`. Runtime Prisma access must use
  `api/_prisma_client.js` because Prisma 7 requires the `@prisma/adapter-pg`
  driver adapter. SQL migrations in `oracle-postgres/schema/` remain canonical
  unless a Prisma migration plan is explicitly reviewed.

## Hermes / Flareon (linked, not duplicated)

- Hermes/Flareon/Poko use Honcho `hermes-peer1` and run on peer1.
- Flareon reads **`pokoin-handoff.md`** (synced to `/opt/hermes-flareon/data/`) for what Giuseppe is doing in Pokoin/Cursor — summaries only.
- Do not copy full Pokoin code or entire Cursor logs into `hermes-peer1`.

## Assistant integrations

- **Codevira**: MCP server `codevira` — decision log under `.codevira/` (includes locked secrets-path decisions `D000001`–`D000004`)
- **Honcho (peer1 Docker)**: MCP `honcho-pokoin` → SSH tunnel + local wrangler; workspace `pokoin-cursor`
- **Secrets map**: `memory/secrets-workflow.md` (paths only, no values)
