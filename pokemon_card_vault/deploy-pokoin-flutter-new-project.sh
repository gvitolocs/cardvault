#!/usr/bin/env bash
# Deploy the Flutter CardVault web app to a NEW Vercel project.
# Does not alias pokoin.com. Does not overwrite the production `web` project link.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERCEL_ORG_ID="${VERCEL_ORG_ID:-team_WIppHrH49qzR3JDOj6AynDiC}"
FLUTTER_PROJECT_NAME="${FLUTTER_PROJECT_NAME:-pokoin-flutter}"
ORACLE_API_BASE_URL="${ORACLE_API_BASE_URL:-https://api.pokoin.com}"
ORACLE_API_BASE_URL="${ORACLE_API_BASE_URL%/}"

cd "$ROOT_DIR"

if [[ -z "${FLUTTER_PROJECT_ID:-}" ]]; then
  echo "Creating or resolving Vercel project ${FLUTTER_PROJECT_NAME}..."
  vercel project add "$FLUTTER_PROJECT_NAME" --scope "$VERCEL_ORG_ID" --non-interactive >/dev/null || true
  FLUTTER_PROJECT_ID="$(
    vercel project inspect "$FLUTTER_PROJECT_NAME" --scope "$VERCEL_ORG_ID" 2>/dev/null \
      | python3 -c "
import re, sys
text = sys.stdin.read()
match = re.search(r'prj_[A-Za-z0-9]+', text)
if not match:
    sys.exit(1)
print(match.group(0))
"
  )"
fi

if [[ -z "${FLUTTER_PROJECT_ID:-}" ]]; then
  echo "ERROR: could not resolve Vercel project id for ${FLUTTER_PROJECT_NAME}." >&2
  exit 1
fi

echo "Using Vercel project ${FLUTTER_PROJECT_NAME} (${FLUTTER_PROJECT_ID})"

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

flutter build web --release --pwa-strategy=none --no-wasm-dry-run "${FLUTTER_DEFINES[@]}"

rm -rf "$ROOT_DIR/build/web/api" "$ROOT_DIR/build/web/server"
if [[ -d "$ROOT_DIR/web/api" ]]; then
  mkdir -p "$ROOT_DIR/build/web/api"
  cp -R "$ROOT_DIR/web/api/." "$ROOT_DIR/build/web/api/"
  find "$ROOT_DIR/build/web/api" -type f -name '*.js' -delete
fi
rm -f "$ROOT_DIR/build/web/package.json" "$ROOT_DIR/build/web/package-lock.json"
cp "$ROOT_DIR/vercel.json" "$ROOT_DIR/build/web/vercel.json"

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

rewrites = []
for rewrite in config.get("rewrites", []):
    source = rewrite.get("source", "")
    destination = str(rewrite.get("destination", ""))
    # Flutter owns /cardscan. Public-id shortlinks proxy to api.pokoin.com.
    if source in ("/cardscan", "/cardscan/", "/scancard", "/scancard/"):
        continue
    if is_local_api_js(destination):
        if source.startswith("/api/") and source != "/api/ensure-username":
            rewrite["destination"] = f"{api_base}{source}"
        else:
            path_part, query = strip_js(destination)
            rewrite["destination"] = f"{api_base}{path_part}{query}"
    rewrites.append(rewrite)

catchall = {
    "source": "/api/:path*",
    "destination": f"{api_base}/api/:path*",
}
if not any(
    rewrite.get("source") == catchall["source"]
    and rewrite.get("destination") == catchall["destination"]
    for rewrite in rewrites
):
    last_api = max(
        (i for i, rewrite in enumerate(rewrites) if "/api/" in str(rewrite.get("destination", ""))),
        default=len(rewrites) - 1,
    )
    rewrites.insert(last_api + 1, catchall)
config["rewrites"] = rewrites

# Do not send this project's index.html (or legacy html) to pokoin.com.
redirects = []
for redirect in config.get("redirects", []):
    destination = str(redirect.get("destination", ""))
    has_host = any(
        item.get("type") == "host" for item in redirect.get("has") or []
    )
    if destination.startswith("https://pokoin.com") and not has_host:
        continue
    redirects.append(redirect)
config["redirects"] = redirects

path.write_text(json.dumps(config, indent=2) + "\n")
PY

if ! grep -q '/api/wallet-auth/nonce' "$ROOT_DIR/build/web/main.dart.js"; then
  echo "ERROR: wallet auth endpoint missing from compiled Flutter bundle." >&2
  exit 1
fi
if ! grep -q 'cardscan' "$ROOT_DIR/build/web/main.dart.js"; then
  echo "ERROR: card scan code missing from compiled Flutter bundle." >&2
  exit 1
fi

STAGING="$(mktemp -d /tmp/pokoin-flutter-vercel-XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
rsync -a --exclude '.vercel' "$ROOT_DIR/build/web/" "$STAGING/"
mkdir -p "$STAGING/.vercel"
printf '{"projectId":"%s","orgId":"%s","projectName":"%s"}\n' \
  "$FLUTTER_PROJECT_ID" \
  "$VERCEL_ORG_ID" \
  "$FLUTTER_PROJECT_NAME" \
  > "$STAGING/.vercel/project.json"

# Never overwrite the production `web` project link in this repo.
if [[ -f "$ROOT_DIR/.vercel/project.json" ]]; then
  python3 - "$ROOT_DIR/.vercel/project.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
if data.get("projectName") not in (None, "web") and data.get("projectId") != "prj_1x0bUwaSZPeMRU90jQL5Ak8WWnPX":
    raise SystemExit(f"refusing to continue: repo .vercel/project.json is {data}")
PY
fi

cd "$STAGING"
rm -rf "$STAGING/.vercel/output"
vercel pull --yes --environment=production
vercel build --prod --yes
DEPLOYMENT_OUTPUT="$(vercel deploy --prebuilt --prod --yes --archive=tgz)"
echo "$DEPLOYMENT_OUTPUT"
DEPLOYMENT_URL="$(
  DEPLOYMENT_OUTPUT="$DEPLOYMENT_OUTPUT" python3 - <<'PY'
import os, re, sys
output = os.environ.get("DEPLOYMENT_OUTPUT", "")
matches = re.findall(r"(?:https?://)?[a-zA-Z0-9][a-zA-Z0-9.-]*\.vercel\.app", output)
if not matches:
    sys.exit(1)
url = matches[-1]
if not url.startswith("http"):
    url = "https://" + url
print(url)
PY
)"
echo "Flutter website: $DEPLOYMENT_URL"
echo "Card scan: ${DEPLOYMENT_URL}/cardscan"
echo "Did not alias pokoin.com."
