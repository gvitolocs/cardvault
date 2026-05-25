#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

wrangler deploy --config wrangler.pokoin-cdn-card-images.jsonc

echo "Worker route deployed."
echo "Verify https://pokoin.com/card-images/<object-key> returns x-pokoin-cdn-worker: r2-card-images."
echo "The legacy cdn.pokoin.com route is still configured, but app image URLs should use same-origin /card-images paths."
