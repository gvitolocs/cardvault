# Codex agents — Pokoin (app + Obsidian pack)

You are helping a collaborator work on the **Pokoin app** (Flutter / React / APIs).

## Read order

1. `APP_COLLABORATOR.md` — topology, Pi API, what the product can do
2. `docs/pokoin-api.md` + `docs/react-page-apis.md` for the task’s endpoints
3. `docs/marketplace-public-ids.md` before any card URL / image / id work
4. `playbook/obsidian-documentation.md` only when writing Obsidian-style notes
5. `vault/Pokoin/` as read-only knowledge graph snapshot

## Hard rules

1. Production API is **`https://api.pokoin.com` on pi-home** — not Vercel serverless, not dead peer3.
2. Public card id = CardTrader blueprint × 2. Never invent CDN filenames; use API image fields.
3. React web uses **page BFFs** (`marketplace-*-page`). Flutter mobile may use granular marketplace APIs.
4. Auth = Firebase bearer. Never print secrets, tokens, or `.env` values.
5. Do not invent prices/listings — call the API.
6. Live Obsidian vault is `/home/nes/Obsidian/Pokoin` on **pi-cursor**. This pack’s `vault/` is a snapshot only.
7. Never create a second Obsidian vault inside git.

## Quick smoke

- `GET https://api.pokoin.com/healthz`
- `GET https://api.pokoin.com/api/__contract`
- `GET https://api.pokoin.com/api/marketplace-suggest?q=pika`
