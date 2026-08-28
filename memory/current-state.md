# Pokoin / cardvault — current state

Last updated: 2026-05-28

## Active focus

- Pokoin marketplace / CardVault monorepo under `cardvault/`
- Primary app tree: `pokemon_card_vault/`
- Production API: `https://api.pokoin.com` (Oracle peer3)
- Production web: `https://pokoin.com`
- Prisma is now initialized in `pokemon_card_vault/` as a secondary Oracle
  Postgres access layer. It introspects the existing `pokoin_marketplace`
  schema from `MARKETPLACE_DATABASE_URL`; SQL under
  `pokemon_card_vault/oracle-postgres/schema/` remains canonical for DDL.
- English marketplace autocomplete/searchbar is live on Meilisearch in
  production. `api.pokoin.com` runs `MARKETPLACE_SEARCH_ENGINE=meili` for
  `search_language=en`; non-English remains on the legacy Oracle/Supabase path.
  The public `pokoin.com/api/*` production rewrite points to `api.pokoin.com`.

## Memory stack (Cursor)

| Layer | Role |
|-------|------|
| Honcho (`pokoin-cursor` workspace) | Cross-session chat memory via MCP `honcho-pokoin` |
| Codevira | Structured decisions, roadmap, conventions |
| This `memory/` folder | Human-readable backup |

Hermes/Flareon do **not** store full Pokoin code in `hermes-peer1`. Flareon gets a **short summary** via `memory/flareon-handoff.md` (synced to peer1).

## Deploy reminders

- Web production: `ORACLE_API_BASE_URL=https://api.pokoin.com POKOIN_WEB_DEPLOY_TARGET=production ./deploy-pokoin-web.sh`
- API production: `npm run peer3:deploy` from `pokemon_card_vault/`; Meili
  reachability depends on peer3 `pokoin-meili-peer-tunnel.service` and
  `pokoin-meili-marketplace-delta.timer`.
- Prisma checks: from `pokemon_card_vault/`, run `npm run prisma:validate`,
  `npm run prisma:sync`, and `npm run prisma:smoke`.
- See `pokemon_card_vault/workflows/README.md` for CardTrader, Supabase, and competitive rollout steps.
