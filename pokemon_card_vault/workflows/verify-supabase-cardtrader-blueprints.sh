#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
from urllib.request import Request, urlopen
import json


def env_value(key: str) -> str:
    for line in Path(".env.local").read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, raw = stripped.split("=", 1)
        if name.strip().removeprefix("export ").strip() == key:
            return raw.strip().strip('"').strip("'")
    return ""


url = env_value("SUPABASE_URL").rstrip("/")
key = env_value("SUPABASE_SERVICE_ROLE_KEY")
if not url or not key:
    raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Accept": "application/json",
    "Prefer": "count=exact",
}
request = Request(
    f"{url}/rest/v1/cardtrader_pokemon_blueprints?select=id&limit=1",
    headers=headers,
)
with urlopen(request, timeout=30) as response:
    print("content-range", response.headers.get("content-range"))

sample_request = Request(
    f"{url}/rest/v1/cardtrader_pokemon_blueprints?select=id,name,expansion_id,image_url&limit=2&order=id.asc",
    headers={k: v for k, v in headers.items() if k != "Prefer"},
)
with urlopen(sample_request, timeout=30) as response:
    print(json.dumps(json.loads(response.read()), indent=2)[:1200])
PY
