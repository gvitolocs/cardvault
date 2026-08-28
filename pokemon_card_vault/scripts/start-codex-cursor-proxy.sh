#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUTH_PATH="${HOME}/.codex/auth.json"
CONFIG_PATH="${HOME}/.codex/cursor-proxy/config.json"
PROXY_DIR="${ROOT}/tools/codex-cursor-proxy"
PORT="${CODEX_CURSOR_PROXY_PORT:-3000}"

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then
    return 0
  fi

  echo "Bun is required for codex-cursor-proxy."
  echo "Install it with:"
  echo "  curl -fsSL https://bun.sh/install | bash"
  exit 1
}

ensure_codex_auth() {
  if [[ -f "$AUTH_PATH" ]]; then
    return 0
  fi

  echo "Missing ${AUTH_PATH}."
  echo "Run the Codex CLI once and sign in with your ChatGPT account:"
  echo "  codex"
  exit 1
}

ensure_proxy_deps() {
  if [[ ! -d "${PROXY_DIR}/node_modules" ]]; then
    echo "Installing codex-cursor-proxy dependencies..."
    (cd "$PROXY_DIR" && bun install)
  fi
}

check_port() {
  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Port ${PORT} is already in use."
      echo "Stop the other process or set CODEX_CURSOR_PROXY_PORT before starting the proxy."
      exit 1
    fi
  fi
}

print_stable_url_hint() {
  if [[ -f "$CONFIG_PATH" ]]; then
    python3 - <<'PY' "$CONFIG_PATH" 2>/dev/null || true
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
except Exception:
    raise SystemExit
sub = cfg.get("subdomain")
url = cfg.get("tunnelUrl")
if sub:
    print(f"Stable tunnel subdomain: {sub}")
if url:
    print(f"Last known Cursor Base URL: {url}")
PY
  fi
}

print_cursor_setup() {
  cat <<EOF

After startup, copy the printed tunnel URL into Cursor:

  Settings → Models → OpenAI
    Base URL: https://<subdomain>.loca.lt
    API Key:  any non-empty string (for example: x)

Pick a Codex-compatible model name (for example: gpt-5.4).

Full guide: workflows/codex-cursor-proxy-workflow.md
EOF
}

ensure_bun
ensure_codex_auth
ensure_proxy_deps
check_port
print_stable_url_hint
print_cursor_setup

exec bun run "${PROXY_DIR}/index.ts"
