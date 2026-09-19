#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

wrangler deploy --config wrangler.pokoin-cdn-card-images.jsonc

echo "Worker route deployed for pokoin.com/card-images/*."
echo "cdn.pokoin.com is the Pi tunnel origin (not this worker)."
echo "Verify a leftover JPEG returns image/jpeg, not homepage webp:"
echo "  curl -sI https://pokoin.com/card-images/167006_rapidash.jpg"
