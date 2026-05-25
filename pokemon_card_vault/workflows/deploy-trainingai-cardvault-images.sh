#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [ -f ".env.local" ]; then
  cloudflare_exports="$(python3 - <<'PYENV'
from pathlib import Path
import shlex

keys = (
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "CLOUDFLARE_API_EMAIL",
    "CLOUDFLARE_GLOBAL_API_KEY",
)

values = {}
for raw in Path(".env.local").read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    if key in keys and value:
        values[key] = value

for key, value in values.items():
    print(f"export {key}={shlex.quote(value)}")

if "CLOUDFLARE_API_TOKEN" not in values and "CLOUDFLARE_GLOBAL_API_KEY" in values:
    print(f"export CLOUDFLARE_API_KEY={shlex.quote(values['CLOUDFLARE_GLOBAL_API_KEY'])}")

if "CLOUDFLARE_EMAIL" not in values and "CLOUDFLARE_API_EMAIL" in values:
    print(f"export CLOUDFLARE_EMAIL={shlex.quote(values['CLOUDFLARE_API_EMAIL'])}")
PYENV
)"
  eval "${cloudflare_exports}"
fi

wrangler deploy --config wrangler.trainingai-cardvault-images.jsonc

echo "Training AI image Worker route deployed."
echo "Verify https://trainingai.pokoin.com/ returns a Pokoin-styled HTML guide page."
echo "Verify https://trainingai.pokoin.com/manifest.json returns paginated read-only JSON."
echo "Verify https://trainingai.pokoin.com/images/<object-key> returns a card image from cardvault-images."
