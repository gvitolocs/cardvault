#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.local"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

token="$(
  python3 - "${ENV_FILE}" <<'PY'
from pathlib import Path
import sys

env_file = Path(sys.argv[1])
for line in env_file.read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue
    key, raw = stripped.split("=", 1)
    key = key.strip().removeprefix("export ").strip()
    if key == "SUPABASE_SECRET_ACCESS_KEY":
        print(raw.strip().strip('"').strip("'"))
        break
PY
)"

if [[ -z "${token}" ]]; then
  echo "SUPABASE_SECRET_ACCESS_KEY is missing from ${ENV_FILE}" >&2
  exit 1
fi

export SUPABASE_ACCESS_TOKEN="${token}"
exec "$@"
