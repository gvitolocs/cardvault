#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

wrangler deploy scripts/cardcaveau-cdn-security-worker.js \
  --name cardcaveau-cdn-security \
  --compatibility-date 2026-05-17 \
  --route 'cdn.cardcaveau.com/*'

echo "Worker route deployed."
echo "Ensure cdn.cardcaveau.com has a proxied Cloudflare DNS record."
