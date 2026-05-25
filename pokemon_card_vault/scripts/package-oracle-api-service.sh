#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ORACLE_API_BUNDLE_DIR:-$ROOT_DIR/build/oracle-api}"

cd "$ROOT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/api" "$OUT_DIR/server" "$OUT_DIR/scripts" "$OUT_DIR/docs"

cp package.json "$OUT_DIR/package.json"
if [[ -f package-lock.json ]]; then
  cp package-lock.json "$OUT_DIR/package-lock.json"
fi

cp api/*.js "$OUT_DIR/api/"
cp server/*.js "$OUT_DIR/server/"
cp server/ecosystem.config.cjs "$OUT_DIR/ecosystem.config.cjs"
cp scripts/check-oracle-api-server.js "$OUT_DIR/scripts/check-oracle-api-server.js"
cp scripts/refresh-cardtrader-blueprint-listing-cache.js "$OUT_DIR/scripts/refresh-cardtrader-blueprint-listing-cache.js"
cp scripts/refresh-cardtrader-market-listings.js "$OUT_DIR/scripts/refresh-cardtrader-market-listings.js"
cp scripts/run-cardtrader-daily-market-refresh.sh "$OUT_DIR/scripts/run-cardtrader-daily-market-refresh.sh"
cp scripts/smoke-oracle-api-routes.js "$OUT_DIR/scripts/smoke-oracle-api-routes.js"
cp docs/oracle-api-migration.md "$OUT_DIR/docs/oracle-api-migration.md"

cat > "$OUT_DIR/README.md" <<'README'
# Pokoin Oracle API Service Bundle

Run locally or on peer3:

```bash
npm ci --omit=dev
PORT=8080 npm run api:server
```

This bundle does not include `.env.local` or secrets. Provide production
environment variables through the host supervisor or env file.
README

echo "Packaged Oracle API service at $OUT_DIR"
