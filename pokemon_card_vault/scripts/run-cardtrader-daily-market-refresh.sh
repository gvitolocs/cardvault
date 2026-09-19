#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POKOINPOS_ROOT="${POKOINPOS_ROOT:-/Users/giuseppe/pokoinpos}"
ENV_FILE="${CARDTRADER_DAILY_ENV_FILE:-$POKOINPOS_ROOT/deploy/env/peer4-postgres.env}"
NODE_BIN="${NODE_BIN:-/usr/bin/env node}"

MARKET_MAX_BLUEPRINTS="${CARDTRADER_MARKET_MAX_BLUEPRINTS:-100000}"
MARKET_MAX_PRODUCTS="${CARDTRADER_MARKET_MAX_PRODUCTS:-20000000}"
MARKET_MAX_EXPANSIONS="${CARDTRADER_MARKET_MAX_EXPANSIONS:-10000}"
MARKET_REQUEST_DELAY_MS="${CARDTRADER_MARKET_REQUEST_DELAY_MS:-50}"
MARKET_EXPANSION_CONCURRENCY="${CARDTRADER_MARKET_EXPANSION_CONCURRENCY:-4}"
MARKET_PERSIST_CONCURRENCY="${CARDTRADER_MARKET_PERSIST_CONCURRENCY:-1}"
MARKET_SHARD_COUNT="${CARDTRADER_MARKET_SHARD_COUNT:-1}"
MARKET_SHARD_INDEX="${CARDTRADER_MARKET_SHARD_INDEX:-0}"
MARKET_EXTRA_ARGS="${CARDTRADER_MARKET_EXTRA_ARGS:-}"

cd "$ROOT_DIR"

echo "[$(date -Is)] Starting CardTrader daily expansion market import (complete book, parallel sets)"
# shellcheck disable=SC2086
$NODE_BIN scripts/refresh-cardtrader-market-listings.js \
  --env-file="$ENV_FILE" \
  --by-expansion \
  --complete-book \
  --expansion-concurrency="$MARKET_EXPANSION_CONCURRENCY" \
  --persist-concurrency="$MARKET_PERSIST_CONCURRENCY" \
  --shard-count="$MARKET_SHARD_COUNT" \
  --shard-index="$MARKET_SHARD_INDEX" \
  --finalize \
  --max-blueprints="$MARKET_MAX_BLUEPRINTS" \
  --max-products="$MARKET_MAX_PRODUCTS" \
  --max-expansions="$MARKET_MAX_EXPANSIONS" \
  --request-delay-ms="$MARKET_REQUEST_DELAY_MS" \
  $MARKET_EXTRA_ARGS

echo "[$(date -Is)] Finished CardTrader daily expansion market import"
