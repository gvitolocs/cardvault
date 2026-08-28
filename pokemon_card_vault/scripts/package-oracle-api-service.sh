#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ORACLE_API_BUNDLE_DIR:-$ROOT_DIR/build/oracle-api}"

cd "$ROOT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/api" "$OUT_DIR/server" "$OUT_DIR/scripts" "$OUT_DIR/docs" "$OUT_DIR/workflows" "$OUT_DIR/oracle-postgres/schema"
mkdir -p "$OUT_DIR/deploy/systemd"

cp package.json "$OUT_DIR/package.json"
if [[ -f package-lock.json ]]; then
  cp package-lock.json "$OUT_DIR/package-lock.json"
fi

cp api/*.js "$OUT_DIR/api/"
cp server/*.js "$OUT_DIR/server/"
cp server/ecosystem.config.cjs "$OUT_DIR/ecosystem.config.cjs"
cp scripts/check-oracle-api-server.js "$OUT_DIR/scripts/check-oracle-api-server.js"
cp scripts/check-api-guardrails.js "$OUT_DIR/scripts/check-api-guardrails.js"
cp scripts/check-api-route-tests.js "$OUT_DIR/scripts/check-api-route-tests.js"
cp scripts/check-oracle-migrations.js "$OUT_DIR/scripts/check-oracle-migrations.js"
cp scripts/meili-sync-marketplace-full.js "$OUT_DIR/scripts/meili-sync-marketplace-full.js"
cp scripts/meili-sync-name-tokens-full.js "$OUT_DIR/scripts/meili-sync-name-tokens-full.js"
cp scripts/meili-sync-marketplace-delta.js "$OUT_DIR/scripts/meili-sync-marketplace-delta.js"
cp scripts/refresh-cardtrader-blueprint-listing-cache.js "$OUT_DIR/scripts/refresh-cardtrader-blueprint-listing-cache.js"
cp scripts/refresh-cardtrader-market-listings.js "$OUT_DIR/scripts/refresh-cardtrader-market-listings.js"
cp scripts/run-cardtrader-daily-market-refresh.sh "$OUT_DIR/scripts/run-cardtrader-daily-market-refresh.sh"
cp scripts/run-limitless-daily-competitive-sync.sh "$OUT_DIR/scripts/run-limitless-daily-competitive-sync.sh"
cp scripts/sync-limitless-competitive.js "$OUT_DIR/scripts/sync-limitless-competitive.js"
cp scripts/smoke-oracle-api-routes.js "$OUT_DIR/scripts/smoke-oracle-api-routes.js"
cp workflows/api-route-test-coverage.json "$OUT_DIR/workflows/api-route-test-coverage.json"
cp oracle-postgres/schema-manifest.json "$OUT_DIR/oracle-postgres/schema-manifest.json"
cp oracle-postgres/schema/*.sql "$OUT_DIR/oracle-postgres/schema/"
cp deploy/systemd/pokoin-limitless-competitive-sync.service "$OUT_DIR/deploy/systemd/pokoin-limitless-competitive-sync.service"
cp deploy/systemd/pokoin-limitless-competitive-sync.timer "$OUT_DIR/deploy/systemd/pokoin-limitless-competitive-sync.timer"
cp deploy/systemd/pokoin-meili-marketplace-delta.service "$OUT_DIR/deploy/systemd/pokoin-meili-marketplace-delta.service"
cp deploy/systemd/pokoin-meili-marketplace-delta.timer "$OUT_DIR/deploy/systemd/pokoin-meili-marketplace-delta.timer"
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
