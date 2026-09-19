#!/usr/bin/env bash
set -euo pipefail
# Touch + optional search so query paths stay hot. Full residency is
# pokoin-meili-resident.service (vmtouch -l). Do not docker-exec or hit
# SQL autocomplete from here — that fights the 1 GB micro.
DATA="${MEILI_DB_PATH:-/var/lib/meilisearch/data.ms}"
if command -v vmtouch >/dev/null 2>&1 && [[ -e "${DATA}" ]]; then
  vmtouch -t "${DATA}" >/dev/null
fi
curl -fsS --max-time 3 "http://127.0.0.1:7700/health" >/dev/null
KEY="${MEILI_MASTER_KEY:-${MEILI_API_KEY:-}}"
if [[ -n "${KEY}" ]]; then
  curl -fsS --max-time 4 \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    --data '{"q":"a","limit":1}' \
    "http://127.0.0.1:7700/indexes/marketplace_cards/search" >/dev/null
fi
