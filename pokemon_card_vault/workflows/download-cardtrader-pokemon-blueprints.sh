#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/cardtrader-pokemon-blueprints.py \
  --env .env.local \
  --output-dir data/cardtrader \
  --sleep "${CARDTRADER_DOWNLOAD_SLEEP:-0.08}"
