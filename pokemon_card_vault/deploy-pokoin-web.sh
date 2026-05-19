#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_PROJECT_ID="prj_1x0bUwaSZPeMRU90jQL5Ak8WWnPX"
VERCEL_ORG_ID="team_WIppHrH49qzR3JDOj6AynDiC"

cd "$ROOT_DIR"

require_vercel_env() {
  local key="$1"
  local env_list
  if ! env_list="$(vercel env ls 2>/dev/null)"; then
    echo "ERROR: unable to read Vercel environment variables." >&2
    exit 1
  fi
  if ! VERCEL_ENV_LIST="$env_list" python3 - "$key" <<'PY'
import os
import sys

key = sys.argv[1]
for line in os.environ.get("VERCEL_ENV_LIST", "").splitlines():
    parts = line.split()
    if parts and parts[0] == key:
        sys.exit(0)
sys.exit(1)
PY
  then
    echo "ERROR: ${key} is missing in Vercel production env." >&2
    echo "Add it before deploying marketplace APIs that use Oracle Postgres." >&2
    exit 1
  fi
}

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

require_vercel_env MARKETPLACE_DATABASE_URL

flutter build web --release --pwa-strategy=none "${FLUTTER_DEFINES[@]}"

rm -rf "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/server"
for helper in _email _firebase _marketplace_db _native_pkn _pending_signup _pkn_purchase _r2 _supabase _username _wpkn_exchange; do
  cp "$ROOT_DIR/api/${helper}.js" "$ROOT_DIR/build/web/server/${helper}.js"
done
for endpoint in \
  cache-google-profile-picture \
  cardmarket-redirect \
  cardtrader-redirect \
  create-pkn-checkout-session \
  forum \
  forum-create-post \
  forum-create-topic \
  forum-upload-media \
  marketplace-card-versions \
  marketplace-cards \
  marketplace-event \
  marketplace-expansion-symbols \
  marketplace-expansions \
  marketplace-autocomplete \
  marketplace-home \
  marketplace-search-candidates \
  register-email \
  remove-profile-picture \
  request-pkn-withdraw \
  search-recipient-emails \
  signup-notification \
  stripe-webhook \
  top-up-account-balance \
  transfer-account-balance \
  unlock-silver \
  upload-profile-picture \
  verify-email-signup \
  wallet-auth-nonce \
  wallet-auth-verify \
  wallet-link \
  wallet-link-complete \
  wallet-link-session \
  wpkn-exchange; do
  cp "$ROOT_DIR/api/${endpoint}.js" "$ROOT_DIR/build/web/api/${endpoint}.js"
done
for marketplace_endpoint in cardmarket-redirect marketplace-card-versions marketplace-cards marketplace-event marketplace-expansion-symbols marketplace-expansions marketplace-home marketplace-search-candidates; do
  sed -i.bak "s|require('./_marketplace_db')|require('../server/_marketplace_db')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_firebase')|require('../server/_firebase')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  rm -f "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js.bak"
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
