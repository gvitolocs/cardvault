#!/usr/bin/env bash
# Deprecated wrapper — global MCP uses ~/.cursor/mcp.json → Hermes/scripts/cursor-honcho-mcp.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CURSOR_PROJECT_DIR="${CURSOR_PROJECT_DIR:-$ROOT}"
exec "$HOME/Hermes/scripts/cursor-honcho-mcp.sh" "$@"
