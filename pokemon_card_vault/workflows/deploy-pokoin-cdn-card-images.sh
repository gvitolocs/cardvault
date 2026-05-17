#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

wrangler deploy scripts/pokoin-cdn-card-images-worker.js \
  --name pokoin-cdn-card-images \
  --compatibility-date 2026-05-17 \
  --route 'cdn.pokoin.com/*'

echo "Worker route deployed."
echo "Ensure cdn.pokoin.com has a proxied Cloudflare DNS record before relying on this hostname."
