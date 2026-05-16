#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_PROJECT_ID="prj_1x0bUwaSZPeMRU90jQL5Ak8WWnPX"
VERCEL_ORG_ID="team_WIppHrH49qzR3JDOj6AynDiC"

cd "$ROOT_DIR"

flutter build web --release --pwa-strategy=none

cp -R "$ROOT_DIR/api" "$ROOT_DIR/build/web/api"
cp "$ROOT_DIR/package.json" "$ROOT_DIR/build/web/package.json"
if [[ -f "/Users/giuseppe/pokoinpos/deploy/bootstrap/bootstrap-peers.json" ]]; then
  cp "/Users/giuseppe/pokoinpos/deploy/bootstrap/bootstrap-peers.json" "$ROOT_DIR/build/web/bootstrap-peers.json"
fi
if [[ -f "$ROOT_DIR/package-lock.json" ]]; then
  cp "$ROOT_DIR/package-lock.json" "$ROOT_DIR/build/web/package-lock.json"
fi

mkdir -p "$ROOT_DIR/.vercel" "$ROOT_DIR/build/web/.vercel"
printf '{"projectId":"%s","orgId":"%s","projectName":"web"}\n' \
  "$WEB_PROJECT_ID" \
  "$VERCEL_ORG_ID" \
  > "$ROOT_DIR/.vercel/project.json"
cp "$ROOT_DIR/.vercel/project.json" "$ROOT_DIR/build/web/.vercel/project.json"

cd "$ROOT_DIR/build/web"
vercel deploy --prod --yes
