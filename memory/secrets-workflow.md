# Secrets workflow (Pokoin + Hermes + Flareon)

**Codevira (locked):** `D000001`–`D000004` in `AGENTS.md` / `.codevira/decisions.jsonl`.  
Never paste secret values into Codevira, Honcho, or git.

## Quick map

| Project / role | What | Where (local Mac) | Production |
|----------------|------|-------------------|------------|
| **Pokoin app** | Stripe, DB, Oracle API, app tokens | `pokemon_card_vault/.env.local` | peer3 / server env |
| **Cursor + Honcho (Pokoin)** | `local-dev-key`, workspace `pokoin-cursor`, tunnel → peer1 | `cardvault/.env.honcho.local` | peer1 `:8000` (Docker) |
| **Hermes / Flareon operator** | Telegram, Gmail OAuth, SSH, OpenAI/Codex, monitors | `~/Hermes/private/flareon/` | `/opt/hermes-flareon/secrets/` |
| **Flareon ↔ Pokoin summary** | No secrets — bullets only | `memory/flareon-handoff.md` | `/opt/hermes-flareon/data/pokoin-handoff.md` |

## Honcho (Cursor MCP `honcho-pokoin` → peer1 Docker)

1. Copy `cardvault/.env.example` → `.env.honcho.local` (`HONCHO_API_KEY=local-dev-key`).
2. One-time: `./scripts/install-honcho-mcp-local.sh` (syncs `/opt/honcho/mcp` from peer1).
3. Cursor runs `scripts/cursor-honcho-mcp.sh`: SSH tunnel `:18765` → peer1 Honcho API, local wrangler MCP `:18787`.
4. Restart Cursor after MCP/env changes.

No Honcho Cloud billing. Same Honcho **instance** as Hermes bots; use workspace `pokoin-cursor` (not `hermes-peer1`) for Cursor.

## Hermes / Flareon

- Canonical local tree: `~/Hermes/private/flareon/` (see `~/Hermes/docs/flareon-secrets.md`)
- Symlink `~/Hermes/.env.local` and `apikeys` → `private/flareon/` when possible
- SSH keys: `private/flareon/keys/peer1/peer1.key` (and peer2–4)
- Push to peer1: `~/Hermes/scripts/sync-flareon-secrets-peer1.sh`
- Deploy scripts: `~/Hermes/scripts/flareon-secrets.sh` (resolves peer1 key path)

## Flareon handoff (not secrets)

```bash
cd /Users/giuseppe/cardvault && ./scripts/sync-flareon-handoff-peer1.sh
```

## Pokoin app (do not put in Flareon folder)

- `pokemon_card_vault/.env.local` — payment, auth, DB
- Critical-area rules: `memory/security-rules.md`

## Agent rules

- Redact values in chat, logs, and memory updates (variable names + paths only).
- Do not commit `.env.local`, `.env.honcho.local`, `private/`, or `apikeys` contents.
