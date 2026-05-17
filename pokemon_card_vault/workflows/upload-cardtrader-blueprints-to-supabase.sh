#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 scripts/upload-cardtrader-blueprints-postgrest.py \
  --env .env.local \
  --input data/cardtrader/pokemon-blueprints.jsonl \
  --batch-size "${SUPABASE_UPLOAD_BATCH_SIZE:-250}"
