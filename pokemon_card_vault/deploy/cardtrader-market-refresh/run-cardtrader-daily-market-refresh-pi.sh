#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=/srv/pokoin/cardtrader-refresh
CURRENT="$APP_ROOT/current"
ENV_FILE=/srv/pokoin/api/.env

exec /usr/bin/docker run --rm \
  --network host \
  --stop-timeout 120 \
  --env-file "$ENV_FILE" \
  -e CARDTRADER_DAILY_ENV_FILE=/app/.env.oracle-cardtrader-import \
  -e POKOINPOS_ROOT=/app \
  -e CARDTRADER_MARKET_EXTRA_ARGS="${CARDTRADER_MARKET_EXTRA_ARGS:-}" \
  -e NODE_OPTIONS=--max-old-space-size=768 \
  -v "$CURRENT:/app" \
  -v "$ENV_FILE:/app/.env.oracle-cardtrader-import:ro" \
  -w /app \
  node:20-bookworm \
  bash scripts/run-cardtrader-daily-market-refresh.sh
