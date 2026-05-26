#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LIMITLESS_DAILY_ENV_FILE:-${MARKETPLACE_ENV_FILE:-$ROOT_DIR/.env}}"
NODE_BIN="${NODE_BIN:-/usr/bin/env node}"

MAX_TOURNAMENTS="${LIMITLESS_DAILY_MAX_TOURNAMENTS:-100}"
PUBLIC_DECK_LIMIT="${LIMITLESS_DAILY_PUBLIC_DECK_LIMIT:-50}"
PUBLIC_TOURNAMENT_LIMIT="${LIMITLESS_DAILY_PUBLIC_TOURNAMENT_LIMIT:-50}"
PUBLIC_DECK_RESULT_LIMIT="${LIMITLESS_DAILY_PUBLIC_DECK_RESULT_LIMIT:-120}"
PUBLIC_DECKLIST_LIMIT="${LIMITLESS_DAILY_PUBLIC_DECKLIST_LIMIT:-24}"
REQUEST_DELAY_MS="${LIMITLESS_DAILY_REQUEST_DELAY_MS:-500}"
GAMES="${LIMITLESS_DAILY_GAMES:-PTCG}"
EXTRA_ARGS="${LIMITLESS_DAILY_EXTRA_ARGS:-}"

cd "$ROOT_DIR"

echo "[$(date -Is)] Starting Limitless competitive daily sync"
# shellcheck disable=SC2086
$NODE_BIN scripts/sync-limitless-competitive.js \
  --apply \
  --env-file="$ENV_FILE" \
  --games="$GAMES" \
  --max-tournaments="$MAX_TOURNAMENTS" \
  --public-deck-limit="$PUBLIC_DECK_LIMIT" \
  --public-tournament-limit="$PUBLIC_TOURNAMENT_LIMIT" \
  --public-deck-result-limit="$PUBLIC_DECK_RESULT_LIMIT" \
  --public-decklist-limit="$PUBLIC_DECKLIST_LIMIT" \
  --request-delay-ms="$REQUEST_DELAY_MS" \
  $EXTRA_ARGS

echo "[$(date -Is)] Finished Limitless competitive daily sync"
