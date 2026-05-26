#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_PROJECT_ID="prj_1x0bUwaSZPeMRU90jQL5Ak8WWnPX"
VERCEL_ORG_ID="team_WIppHrH49qzR3JDOj6AynDiC"
POKOINPOS_ROOT="${POKOINPOS_ROOT:-/Users/giuseppe/pokoinpos}"
POKOINPOS_BOOTSTRAP_PEERS_FILE="${POKOINPOS_BOOTSTRAP_PEERS_FILE:-$POKOINPOS_ROOT/deploy/bootstrap/bootstrap-peers.json}"

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
    echo "Add it before deploying the web/API gateway." >&2
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
ORACLE_API_BASE_URL="${ORACLE_API_BASE_URL:-$(read_env_value ORACLE_API_BASE_URL)}"
USE_ORACLE_API="${USE_ORACLE_API:-$(read_env_value USE_ORACLE_API)}"

USE_ORACLE_API_MODE=0
if [[ -n "${ORACLE_API_BASE_URL:-}" || "${USE_ORACLE_API:-}" == "1" ]]; then
  USE_ORACLE_API_MODE=1
  if [[ -z "${ORACLE_API_BASE_URL:-}" ]]; then
    echo "ERROR: USE_ORACLE_API=1 requires ORACLE_API_BASE_URL." >&2
    exit 1
  fi
  ORACLE_API_BASE_URL="${ORACLE_API_BASE_URL%/}"
fi

FLUTTER_DEFINES=()
if [[ -n "${SUPABASE_URL:-}" ]]; then
  FLUTTER_DEFINES+=(--dart-define="SUPABASE_URL=$SUPABASE_URL")
fi
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  FLUTTER_DEFINES+=(--dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")
fi

if [[ "$USE_ORACLE_API_MODE" != "1" ]]; then
  require_vercel_env MARKETPLACE_DATABASE_URL
  require_vercel_env MARKETPLACE_NAME_SEARCH_DATABASE_URL
  require_vercel_env MARKETPLACE_NAME_SEARCH_TIMEOUT_MS
  require_vercel_env MARKETPLACE_NAME_SEARCH_CIRCUIT_MS
  require_vercel_env CARDTRADER_TOKEN_ENCRYPTION_KEY
  require_vercel_env SUPABASE_URL
  require_vercel_env SUPABASE_ANON_KEY
  require_vercel_env SUPABASE_SERVICE_ROLE_KEY
  require_vercel_env POKONTACT_SERVICE_TOKEN
fi

flutter build web --release --pwa-strategy=none "${FLUTTER_DEFINES[@]}"

if [[ "$USE_ORACLE_API_MODE" == "1" ]]; then
  rm -rf "$ROOT_DIR/build/web/api" "$ROOT_DIR/build/web/server"
  if [[ -d "$ROOT_DIR/web/api" ]]; then
    cp -R "$ROOT_DIR/web/api" "$ROOT_DIR/build/web/api"
  fi
else
rm -rf "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/api"
mkdir -p "$ROOT_DIR/build/web/server"
for helper in _bitcoin_payout _cardtrader_client _cardtrader_crypto _cardtrader_daily_listings_refresh _cardtrader_integration _crypto_pkn_purchase _email _firebase _firebase_roles _marketplace_card_emoji _marketplace_card_rarity _marketplace_cart_analytics _marketplace_db _marketplace_sale_notifications _marketplace_watchlist_analytics _native_pkn _pending_signup _pkn_checkout_pricing _pkn_purchase _r2 _search_debug_auth _searchbar_session _social_autoposter _supabase _username _wpkn_exchange; do
  cp "$ROOT_DIR/api/${helper}.js" "$ROOT_DIR/build/web/server/${helper}.js"
done
for endpoint in \
  cache-google-profile-picture \
  cardmarket-redirect \
  cardmarket-scrape-observation \
  cardtrader-blueprint-listings \
  cardtrader-clean-listings \
  cardtrader-connect \
  cardtrader-daily-listings-refresh \
  cardtrader-disconnect \
  cardtrader-import-dry-run \
  cardtrader-live-listings \
  cardtrader-redirect \
  cardtrader-status \
  create-pkn-checkout-session \
  deck-card-version-lookup \
  crypto-pkn-purchase \
  crypto-pkn-sale \
  extension-card-search \
  flutter-debug-logs \
  forum \
  forum-create-post \
  forum-create-topic \
  forum-upload-media \
  marketplace-artist-cards \
  limitless-expansion-blueprints \
  marketplace-blueprint-price \
  marketplace-card-cheapest-price \
  marketplace-card-versions \
  marketplace-card-seo \
  marketplace-card-sales \
  marketplace-card-shortlink \
  marketplace-card-url \
  marketplace-cards \
  marketplace-cardmarket-guess-review \
  marketplace-debug-cardtrader-blueprints \
  marketplace-debug-artists \
  marketplace-debug-events \
  marketplace-debug-refinement \
  marketplace-event \
  marketplace-listings \
  marketplace-expansion-symbols \
  marketplace-expansions \
  marketplace-autocomplete \
  marketplace-hot-blueprints \
  marketplace-home \
  marketplace-search-candidates \
  marketplace-orders \
  searchbar-cancel \
  searchbar-cards \
  searchbar-token-predict \
  social-autopost \
  social-autopost-hot-card \
  social-post-agent \
  pokoin-assistant \
  user-current-page \
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
for marketplace_endpoint in cardmarket-redirect cardmarket-scrape-observation cardtrader-blueprint-listings cardtrader-clean-listings cardtrader-connect cardtrader-daily-listings-refresh cardtrader-disconnect cardtrader-import-dry-run cardtrader-live-listings cardtrader-status deck-card-version-lookup extension-card-search flutter-debug-logs limitless-expansion-blueprints marketplace-artist-cards marketplace-autocomplete marketplace-blueprint-price marketplace-card-cheapest-price marketplace-card-sales marketplace-card-seo marketplace-card-shortlink marketplace-card-url marketplace-card-versions marketplace-cards marketplace-cardmarket-guess-review marketplace-debug-cardtrader-blueprints marketplace-debug-artists marketplace-debug-events marketplace-debug-refinement marketplace-event marketplace-listings marketplace-orders marketplace-expansion-symbols marketplace-expansions marketplace-hot-blueprints marketplace-home marketplace-search-candidates searchbar-cards searchbar-token-predict user-current-page; do
  sed -i.bak "s|require('./_marketplace_db')|require('../server/_marketplace_db')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_marketplace_db")|require("../server/_marketplace_db")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_marketplace_card_emoji')|require('../server/_marketplace_card_emoji')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_marketplace_card_emoji")|require("../server/_marketplace_card_emoji")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_marketplace_card_rarity')|require('../server/_marketplace_card_rarity')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_marketplace_card_rarity")|require("../server/_marketplace_card_rarity")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_marketplace_cart_analytics')|require('../server/_marketplace_cart_analytics')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_marketplace_cart_analytics")|require("../server/_marketplace_cart_analytics")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_marketplace_watchlist_analytics')|require('../server/_marketplace_watchlist_analytics')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_marketplace_watchlist_analytics")|require("../server/_marketplace_watchlist_analytics")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_firebase')|require('../server/_firebase')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_firebase")|require("../server/_firebase")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_firebase_roles')|require('../server/_firebase_roles')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_firebase_roles")|require("../server/_firebase_roles")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_supabase')|require('../server/_supabase')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_supabase")|require("../server/_supabase")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak "s|require('./_pkn_checkout_pricing')|require('../server/_pkn_checkout_pricing')|" \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  sed -i.bak 's|require("./_pkn_checkout_pricing")|require("../server/_pkn_checkout_pricing")|' \
    "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js"
  rm -f "$ROOT_DIR/build/web/api/${marketplace_endpoint}.js.bak"
done
sed -i.bak "s|require('./_marketplace_sale_notifications')|require('../server/_marketplace_sale_notifications')|" \
  "$ROOT_DIR/build/web/api/marketplace-orders.js"
sed -i.bak 's|require("./_marketplace_sale_notifications")|require("../server/_marketplace_sale_notifications")|' \
  "$ROOT_DIR/build/web/api/marketplace-orders.js"
rm -f "$ROOT_DIR/build/web/api/marketplace-orders.js.bak"
sed -i.bak "s|require('./_email')|require('../server/_email')|" \
  "$ROOT_DIR/build/web/server/_marketplace_sale_notifications.js"
sed -i.bak 's|require("./_email")|require("../server/_email")|' \
  "$ROOT_DIR/build/web/server/_marketplace_sale_notifications.js"
rm -f "$ROOT_DIR/build/web/server/_marketplace_sale_notifications.js.bak"
for cardtrader_endpoint in cardtrader-clean-listings cardtrader-connect cardtrader-daily-listings-refresh cardtrader-disconnect cardtrader-import-dry-run cardtrader-live-listings cardtrader-status; do
  for helper in _cardtrader_client _cardtrader_crypto _cardtrader_daily_listings_refresh _cardtrader_integration; do
    sed -i.bak "s|require('./${helper}')|require('../server/${helper}')|" \
      "$ROOT_DIR/build/web/api/${cardtrader_endpoint}.js"
    sed -i.bak "s|require(\"./${helper}\")|require(\"../server/${helper}\")|" \
      "$ROOT_DIR/build/web/api/${cardtrader_endpoint}.js"
    rm -f "$ROOT_DIR/build/web/api/${cardtrader_endpoint}.js.bak"
  done
done
for search_debug_endpoint in flutter-debug-logs marketplace-autocomplete marketplace-cardmarket-guess-review marketplace-debug-cardtrader-blueprints marketplace-debug-artists marketplace-debug-events marketplace-debug-refinement marketplace-search-candidates searchbar-cards searchbar-token-predict; do
  sed -i.bak "s|require('./_search_debug_auth')|require('../server/_search_debug_auth')|" \
    "$ROOT_DIR/build/web/api/${search_debug_endpoint}.js"
  sed -i.bak 's|require("./_search_debug_auth")|require("../server/_search_debug_auth")|' \
    "$ROOT_DIR/build/web/api/${search_debug_endpoint}.js"
  rm -f "$ROOT_DIR/build/web/api/${search_debug_endpoint}.js.bak"
done
for searchbar_session_endpoint in marketplace-autocomplete searchbar-cancel searchbar-cards searchbar-token-predict; do
  sed -i.bak "s|require('./_searchbar_session')|require('../server/_searchbar_session')|" \
    "$ROOT_DIR/build/web/api/${searchbar_session_endpoint}.js"
  sed -i.bak 's|require("./_searchbar_session")|require("../server/_searchbar_session")|' \
    "$ROOT_DIR/build/web/api/${searchbar_session_endpoint}.js"
  rm -f "$ROOT_DIR/build/web/api/${searchbar_session_endpoint}.js.bak"
done
for crypto_endpoint in crypto-pkn-purchase crypto-pkn-sale; do
  for helper in _bitcoin_payout _crypto_pkn_purchase _firebase _native_pkn; do
    sed -i.bak "s|require('../server/${helper}')|require('../server/${helper}')|" \
      "$ROOT_DIR/build/web/api/${crypto_endpoint}.js"
    sed -i.bak "s|require(\"../server/${helper}\")|require(\"../server/${helper}\")|" \
      "$ROOT_DIR/build/web/api/${crypto_endpoint}.js"
    sed -i.bak "s|require('./${helper}')|require('../server/${helper}')|" \
      "$ROOT_DIR/build/web/api/${crypto_endpoint}.js"
    sed -i.bak "s|require(\"./${helper}\")|require(\"../server/${helper}\")|" \
      "$ROOT_DIR/build/web/api/${crypto_endpoint}.js"
    rm -f "$ROOT_DIR/build/web/api/${crypto_endpoint}.js.bak"
  done
done
fi
if [[ "$USE_ORACLE_API_MODE" == "1" ]]; then
  rm -f "$ROOT_DIR/build/web/package.json" "$ROOT_DIR/build/web/package-lock.json"
else
  cp "$ROOT_DIR/package.json" "$ROOT_DIR/build/web/package.json"
fi
cp "$ROOT_DIR/vercel.json" "$ROOT_DIR/build/web/vercel.json"
if [[ -f "$POKOINPOS_BOOTSTRAP_PEERS_FILE" ]]; then
  cp "$POKOINPOS_BOOTSTRAP_PEERS_FILE" "$ROOT_DIR/build/web/bootstrap-peers.json"
fi
if [[ "$USE_ORACLE_API_MODE" != "1" && -f "$ROOT_DIR/package-lock.json" ]]; then
  cp "$ROOT_DIR/package-lock.json" "$ROOT_DIR/build/web/package-lock.json"
fi
if [[ "$USE_ORACLE_API_MODE" == "1" ]]; then
  python3 - "$ROOT_DIR/build/web/vercel.json" "$ORACLE_API_BASE_URL" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
api_base = sys.argv[2].rstrip("/")
config = json.loads(path.read_text())
config.pop("functions", None)

def split_query(destination):
    if "?" not in destination:
        return destination, ""
    path_part, query = destination.split("?", 1)
    return path_part, f"?{query}"

def strip_js(destination):
    path_part, query = split_query(destination)
    if path_part.startswith("/api/") and path_part.endswith(".js"):
        path_part = path_part[:-3]
    return path_part, query

def is_local_api_js(destination):
    path_part, _ = split_query(destination)
    return path_part.startswith("/api/") and path_part.endswith(".js")

rewrites = config.get("rewrites", [])
last_api_rewrite_index = -1
for index, rewrite in enumerate(rewrites):
    source = rewrite.get("source", "")
    destination = rewrite.get("destination", "")
    if is_local_api_js(destination):
        if source.startswith("/api/") and source != "/api/ensure-username":
            rewrite["destination"] = f"{api_base}{source}"
        else:
            path_part, query = strip_js(destination)
            rewrite["destination"] = f"{api_base}{path_part}{query}"
        last_api_rewrite_index = index
    elif source.startswith("/api/") or str(destination).startswith(f"{api_base}/api/"):
        last_api_rewrite_index = index

catchall = {
    "source": "/api/:path*",
    "destination": f"{api_base}/api/:path*",
}
if not any(
    rewrite.get("source") == catchall["source"]
    and rewrite.get("destination") == catchall["destination"]
    for rewrite in rewrites
):
    rewrites.insert(last_api_rewrite_index + 1, catchall)

config["rewrites"] = rewrites
path.write_text(json.dumps(config, indent=2) + "\n")
PY
fi

if [[ "$USE_ORACLE_API_MODE" == "1" ]]; then
if ! grep -q '/api/wallet-auth/nonce' "$ROOT_DIR/build/web/main.dart.js"; then
  echo "ERROR: wallet auth endpoint missing from compiled Flutter bundle." >&2
  exit 1
fi
if [[ -d "$ROOT_DIR/build/web/api" ]] && find "$ROOT_DIR/build/web/api" -type f -name '*.js' -print -quit | grep -q .; then
  echo "ERROR: Oracle API mode must not copy Vercel API function files." >&2
  exit 1
fi
else
if ! grep -q '/api/wallet-auth/nonce' "$ROOT_DIR/build/web/main.dart.js"; then
  echo "ERROR: wallet auth endpoint missing from compiled Flutter bundle." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/wallet-auth-nonce.js" || ! -f "$ROOT_DIR/build/web/api/wallet-auth-verify.js" ]]; then
  echo "ERROR: wallet auth API files missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/crypto-pkn-purchase.js" || ! -f "$ROOT_DIR/build/web/api/crypto-pkn-sale.js" || ! -f "$ROOT_DIR/build/web/server/_crypto_pkn_purchase.js" ]]; then
  echo "ERROR: crypto PKN API files missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/marketplace-blueprint-price.js" ]]; then
  echo "ERROR: marketplace blueprint price API missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/marketplace-card-cheapest-price.js" ]]; then
  echo "ERROR: marketplace card cheapest price API missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/server/_pkn_checkout_pricing.js" ]]; then
  echo "ERROR: PKN checkout pricing helper missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/marketplace-card-seo.js" || ! -f "$ROOT_DIR/build/web/api/marketplace-card-sales.js" || ! -f "$ROOT_DIR/build/web/api/marketplace-card-versions.js" || ! -f "$ROOT_DIR/build/web/api/deck-card-version-lookup.js" || ! -f "$ROOT_DIR/build/web/api/limitless-expansion-blueprints.js" || ! -f "$ROOT_DIR/build/web/api/marketplace-orders.js" || ! -f "$ROOT_DIR/build/web/api/flutter-debug-logs.js" || ! -f "$ROOT_DIR/build/web/server/_marketplace_sale_notifications.js" ]]; then
  echo "ERROR: marketplace SEO/orders API files missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/server/_marketplace_watchlist_analytics.js" || ! -f "$ROOT_DIR/build/web/server/_marketplace_cart_analytics.js" ]]; then
  echo "ERROR: marketplace analytics helpers missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/server/_supabase.js" ]]; then
  echo "ERROR: Supabase helper missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/server/_firebase_roles.js" ]]; then
  echo "ERROR: Firebase roles helper missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/pokoin-assistant.js" || ! -f "$ROOT_DIR/build/web/api/user-current-page.js" || ! -f "$ROOT_DIR/build/web/server/_firebase.js" || ! -f "$ROOT_DIR/build/web/server/_email.js" || ! -f "$ROOT_DIR/build/web/server/_marketplace_db.js" ]]; then
  echo "ERROR: Pokontact API/helper files missing from Vercel build output." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/build/web/api/social-autopost.js" || ! -f "$ROOT_DIR/build/web/api/social-autopost-hot-card.js" || ! -f "$ROOT_DIR/build/web/api/social-post-agent.js" || ! -f "$ROOT_DIR/build/web/server/_social_autoposter.js" ]]; then
  echo "ERROR: social autoposter API/helper files missing from Vercel build output." >&2
  exit 1
fi
node - "$ROOT_DIR/build/web/api/pokoin-assistant.js" <<'NODE'
const target = process.argv[2];
try {
  const handler = require(target);
  handler._test.loadFirebaseHelper();
  handler._test.loadEmailHelper();
  handler._test.loadMarketplaceDbHelper();
} catch (error) {
  console.error('ERROR: Pokontact API handler/helpers do not load from Vercel build output.');
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
}
NODE
python3 - "$ROOT_DIR/build/web/api/marketplace-autocomplete.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
stale_imports = ("require('./_supabase')", 'require("./_supabase")')
if any(item in source for item in stale_imports):
    print("ERROR: marketplace-autocomplete still imports ./_supabase in Vercel build output.", file=sys.stderr)
    sys.exit(1)
if "require('../server/_supabase')" not in source and 'require("../server/_supabase")' not in source:
    print("ERROR: marketplace-autocomplete does not import the deployed Supabase helper.", file=sys.stderr)
    sys.exit(1)
PY
fi

mkdir -p "$ROOT_DIR/.vercel" "$ROOT_DIR/build/web/.vercel"
printf '{"projectId":"%s","orgId":"%s","projectName":"web"}\n' \
  "$WEB_PROJECT_ID" \
  "$VERCEL_ORG_ID" \
  > "$ROOT_DIR/.vercel/project.json"
cp "$ROOT_DIR/.vercel/project.json" "$ROOT_DIR/build/web/.vercel/project.json"

cd "$ROOT_DIR/build/web"
rm -rf "$ROOT_DIR/build/web/.vercel/output"
POKOIN_WEB_DEPLOY_TARGET="${POKOIN_WEB_DEPLOY_TARGET:-production}"
extract_deployment_url() {
  DEPLOYMENT_OUTPUT="$1" python3 - <<'PY'
import os
import re
import sys

output = os.environ.get("DEPLOYMENT_OUTPUT", "")
matches = re.findall(r"(?:https?://)?[a-zA-Z0-9][a-zA-Z0-9.-]*\.vercel\.app", output)
if not matches:
    sys.exit(1)
print(matches[-1])
PY
}

if [[ "$POKOIN_WEB_DEPLOY_TARGET" == "preview" ]]; then
  vercel pull --yes --environment=preview
  vercel build --yes
  DEPLOYMENT_OUTPUT="$(vercel deploy --prebuilt --yes --archive=tgz)"
  echo "$DEPLOYMENT_OUTPUT"
  if ! DEPLOYMENT_URL="$(extract_deployment_url "$DEPLOYMENT_OUTPUT")"; then
    echo "ERROR: unable to parse Vercel deployment URL." >&2
    exit 1
  fi
  node "$ROOT_DIR/scripts/verify-production-aliases.js" \
    --deployment-url "$DEPLOYMENT_URL" \
    --skip-aliases
else
  vercel pull --yes --environment=production
  vercel build --prod --yes
  DEPLOYMENT_OUTPUT="$(vercel deploy --prebuilt --prod --yes --archive=tgz)"
  echo "$DEPLOYMENT_OUTPUT"
  if ! DEPLOYMENT_URL="$(extract_deployment_url "$DEPLOYMENT_OUTPUT")"; then
    echo "ERROR: unable to parse Vercel deployment URL." >&2
    exit 1
  fi
  node "$ROOT_DIR/scripts/verify-production-aliases.js" \
    --deployment-url "$DEPLOYMENT_URL" \
    --set-aliases
fi
