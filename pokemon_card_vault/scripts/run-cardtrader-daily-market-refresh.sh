#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POKOINPOS_ROOT="${POKOINPOS_ROOT:-/Users/giuseppe/pokoinpos}"
ENV_FILE="${CARDTRADER_DAILY_ENV_FILE:-$POKOINPOS_ROOT/deploy/env/peer4-postgres.env}"
NODE_BIN="${NODE_BIN:-/usr/bin/env node}"

MARKET_MAX_BLUEPRINTS="${CARDTRADER_MARKET_MAX_BLUEPRINTS:-250}"
MARKET_MAX_PRODUCTS="${CARDTRADER_MARKET_MAX_PRODUCTS:-10000}"
MARKET_EXTRA_ARGS="${CARDTRADER_MARKET_EXTRA_ARGS:-}"

CACHE_MAX_BLUEPRINTS="${CARDTRADER_LISTING_CACHE_MAX_BLUEPRINTS:-250}"
CACHE_REFRESH_BATCH_BLUEPRINTS="${CARDTRADER_LISTING_CACHE_REFRESH_BATCH_BLUEPRINTS:-700}"
CACHE_BLUEPRINT_CONCURRENCY="${CARDTRADER_LISTING_CACHE_BLUEPRINT_CONCURRENCY:-1}"
CACHE_REQUEST_DELAY_MS="${CARDTRADER_LISTING_CACHE_REQUEST_DELAY_MS:-500}"
CACHE_PRODUCT_TYPE="${CARDTRADER_LISTING_CACHE_PRODUCT_TYPE:-card}"
CACHE_EXTRA_ARGS="${CARDTRADER_LISTING_CACHE_EXTRA_ARGS:-}"

cd "$ROOT_DIR"

echo "[$(date -Is)] Starting CardTrader daily market listing import"
# shellcheck disable=SC2086
$NODE_BIN scripts/refresh-cardtrader-market-listings.js \
  --env-file="$ENV_FILE" \
  --max-blueprints="$MARKET_MAX_BLUEPRINTS" \
  --max-products="$MARKET_MAX_PRODUCTS" \
  $MARKET_EXTRA_ARGS

echo "[$(date -Is)] Starting CardTrader homepage listing cache refresh"
# shellcheck disable=SC2086
$NODE_BIN scripts/refresh-cardtrader-blueprint-listing-cache.js \
  --env-file="$ENV_FILE" \
  --max-blueprints="$CACHE_MAX_BLUEPRINTS" \
  --refresh-batch-blueprints="$CACHE_REFRESH_BATCH_BLUEPRINTS" \
  --blueprint-concurrency="$CACHE_BLUEPRINT_CONCURRENCY" \
  --request-delay-ms="$CACHE_REQUEST_DELAY_MS" \
  --product-type="$CACHE_PRODUCT_TYPE" \
  $CACHE_EXTRA_ARGS

echo "[$(date -Is)] Finished CardTrader daily market listing import and cache refresh"
