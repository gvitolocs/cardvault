#!/usr/bin/env bash
set -euo pipefail
# Regenerate .env.honcho.local from .env.example (peer1 self-hosted Honcho defaults).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "$ROOT/.env.example" "$ROOT/.env.honcho.local"
chmod 600 "$ROOT/.env.honcho.local"
echo "OK: $ROOT/.env.honcho.local refreshed (peer1 Honcho — HONCHO_API_KEY=local-dev-key)"
echo "Run: ./scripts/install-honcho-mcp-local.sh  # once"
echo "Then restart Cursor (honcho-pokoin MCP)"
