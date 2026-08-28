# Cursor memory setup (Honcho + Codevira)

## Architecture

```
peer1 Docker Honcho (http://127.0.0.1:8000 on server)
    ↑ SSH tunnel :18765 on Mac
    ↑ local MCP worker (wrangler :18787 on Mac)
    ↑ Cursor MCP honcho-pokoin

Workspaces on same Honcho instance:
├── hermes-peer1     → Hermes / Flareon / Poko bots (peer1 Hermes env)
└── pokoin-cursor    → Pokoin / Cursor coding memory (this repo)

Codevira (local structured memory)
└── .codevira/ + AGENTS.md

memory/ (git-backed human backup)
memory/flareon-handoff.md → peer1 for Flareon summary (no code)
```

No **Honcho Cloud** (`hch-...`, app.honcho.dev billing) required for Cursor.

## One-time setup (global Cursor)

Honcho MCP is **global** (`~/.cursor/mcp.json`), not only in this repo:

```bash
cp ~/.cursor/honcho.env.example ~/.cursor/honcho.env
~/Hermes/scripts/install-honcho-mcp.sh
~/Hermes/scripts/honcho-peer1-tunnel.sh ensure
cp .env.example .env.honcho.local   # pokoin-cursor workspace for this repo
```

Restart Cursor.

## MCP servers

| Server | Scope | Purpose |
|--------|-------|---------|
| `honcho` | **Global** `~/.cursor/mcp.json` | peer1 Honcho (all projects) |
| `codevira` | **cardvault** `.cursor/mcp.json` | Project decisions only |

This repo overrides Honcho workspace via `.env.honcho.local` → `pokoin-cursor`.

## Daily use

- Tunnel: `./scripts/honcho-peer1-tunnel.sh status` (Cursor script starts it automatically)
- Workspace for Cursor: `pokoin-cursor`, session label `pokoin-coding`
- API key: `local-dev-key` (peer1 has `AUTH_USE_AUTH=false`)

## Flareon handoff

```bash
./scripts/sync-flareon-handoff-peer1.sh
```

## Verify Honcho

In Cursor: use Honcho MCP `inspect_workspace` or `search` after saving a test message.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Honcho MCP not installed` | `./scripts/install-honcho-mcp-local.sh` |
| Tunnel down | `./scripts/honcho-peer1-tunnel.sh ensure` |
| MCP worker failed | `tail -50 .honcho-mcp-wrangler.log`; need `bun` on Mac |
| Wrong workspace | `HONCHO_WORKSPACE_ID=pokoin-cursor` in `.env.honcho.local` |
| peer1 Honcho down | On peer1: `cd /opt/honcho && sudo docker compose ps` |

## Secrets

See `memory/secrets-workflow.md` and Codevira `AGENTS.md` (D000001–D000004).
