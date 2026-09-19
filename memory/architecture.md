# Architecture (high level)

## Repositories

- `cardvault/` — Cursor workspace root (Codevira + Honcho MCP + memory docs)
- `pokemon_card_vault/` — Flutter web app, Vercel deploy scripts, Oracle API code, Prisma setup
- `oracle-postgres/` — Postgres schema/migrations for Oracle API (when present in tree)

## Runtime topology

- **Web**: Public marketplace is the React SPA in `pokoin-web` (Vercel project `web` → `pokoin.com`). Flutter stays Android/iOS. `/api/*` rewrites to `api.pokoin.com` on **pi-home**.
- **API**: Public `api.pokoin.com` / `cdn.pokoin.com` are Docker on **pi-home** (Cloudflare tunnel), not Vercel serverless and not the Frankfurt first hop. React/JS contract: `pokemon_card_vault/docs/react-api-architecture.md`, `docs/react-page-apis.md`, and `GET /api/__contract`. Page BFFs: `marketplace-card-page`, `marketplace-search-page`, `marketplace-expansion-page`.
- **Search**: English autocomplete/searchbar first-stage retrieval uses
  Meilisearch on **pi-home** localhost next to the API (`127.0.0.1:7700`).
  Postgres hydrates and ranks the final rows. Non-English traffic stays on
  legacy SQL/Supabase search.
- **Data**: Marketplace Postgres **primary** on **pokoin-marketplace** (`130.61.251.250:5432`) is the CardTrader dump / scrape writer (catalog source of truth). The Pi API reads a streaming replica at `127.0.0.1:5432`. nezopt `.env.local` `MARKETPLACE_DATABASE_URL` points at the Oracle primary for migrations and dump jobs. Never `92.5.23.133` or `141.147.62.244`. Never write dumps on the replica. Supabase remains for forum/auth-adjacent tables.
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
- **API host (2026-09-18)**: Confirmed again — production API is **pi-home**, not peer3. peer3 IP is retired.
