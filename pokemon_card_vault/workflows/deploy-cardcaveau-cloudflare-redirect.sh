#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

wrangler deploy scripts/cardcaveau-redirect-worker.js \
  --name cardcaveau-to-pokoin \
  --compatibility-date 2026-05-17 \
  --route 'cardcaveau.com/*' \
  --route 'www.cardcaveau.com/*'

echo "Worker route deployed."
echo "Ensure these Cloudflare DNS records exist and are proxied:"
echo "  A      cardcaveau.com      192.0.2.1"
echo "  CNAME  www                 cardcaveau.com"
