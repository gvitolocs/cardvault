#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_PROJECT_ID="prj_1x0bUwaSZPeMRU90jQL5Ak8WWnPX"
VERCEL_ORG_ID="team_WIppHrH49qzR3JDOj6AynDiC"

cd "$ROOT_DIR"

read_env_value() {
  local key="$1"
  local file="$ROOT_DIR/.env.local"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$key" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
for line in path.read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue
    name, value = stripped.split("=", 1)
    name = name.removeprefix("export ").strip()
    if name == key:
        print(value.strip().strip('"').strip("'"))
        break
PY
}

SUPABASE_URL="${SUPABASE_URL:-$(read_env_value SUPABASE_URL)}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$(read_env_value SUPABASE_ANON_KEY)}"

FLUTTER_DEFINES=()
if [[ -n "${SUPABASE_URL:-}" ]]; then
  FLUTTER_DEFINES+=(--dart-define="SUPABASE_URL=$SUPABASE_URL")
fi
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  FLUTTER_DEFINES+=(--dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")
fi

flutter build web --release --pwa-strategy=none "${FLUTTER_DEFINES[@]}"

rm -rf "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/server"
for helper in _email _firebase _native_pkn _pending_signup _pkn_purchase _r2 _username _wpkn_exchange; do
  cp "$ROOT_DIR/api/${helper}.js" "$ROOT_DIR/build/web/server/${helper}.js"
done
for endpoint in \
  create-pkn-checkout-session \
  marketplace-event \
  marketplace-home \
  register-email \
  remove-profile-picture \
  request-pkn-withdraw \
  search-recipient-emails \
  signup-notification \
  stripe-webhook \
  top-up-account-balance \
  transfer-account-balance \
  upload-profile-picture \
  verify-email-signup \
  wallet-auth-nonce \
  wallet-auth-verify \
  wallet-link \
  wpkn-exchange; do
  cp "$ROOT_DIR/api/${endpoint}.js" "$ROOT_DIR/build/web/api/${endpoint}.js"
done
cp "$ROOT_DIR/package.json" "$ROOT_DIR/build/web/package.json"
cp "$ROOT_DIR/vercel.json" "$ROOT_DIR/build/web/vercel.json"
if [[ -f "/Users/giuseppe/pokoinpos/deploy/bootstrap/bootstrap-peers.json" ]]; then
  cp "/Users/giuseppe/pokoinpos/deploy/bootstrap/bootstrap-peers.json" "$ROOT_DIR/build/web/bootstrap-peers.json"
fi
if [[ -f "$ROOT_DIR/package-lock.json" ]]; then
  cp "$ROOT_DIR/package-lock.json" "$ROOT_DIR/build/web/package-lock.json"
fi

if ! grep -q '/api/wallet-auth/nonce' "$ROOT_DIR/build/web/main.dart.js"; then
  echo "ERROR: wallet auth endpoint missing from compiled Flutter bundle." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/wallet-auth-nonce.js" || ! -f "$ROOT_DIR/build/web/api/wallet-auth-verify.js" ]]; then
  echo "ERROR: wallet auth API files missing from Vercel build output." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/.vercel" "$ROOT_DIR/build/web/.vercel"
printf '{"projectId":"%s","orgId":"%s","projectName":"web"}\n' \
  "$WEB_PROJECT_ID" \
  "$VERCEL_ORG_ID" \
  > "$ROOT_DIR/.vercel/project.json"
cp "$ROOT_DIR/.vercel/project.json" "$ROOT_DIR/build/web/.vercel/project.json"

cd "$ROOT_DIR/build/web"
vercel deploy --prod --yes
