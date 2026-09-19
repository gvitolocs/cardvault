#!/usr/bin/env bash
# Republish Pokoin Codex collaborator pack to Oracle peer1 (rpc.pokoin.com).
# Includes: app/API docs, workflows, memory, Obsidian playbook + vault snapshot.
# Usage: ./scripts/publish-codex-obsidian-pack.sh [--new-token]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PCV="$ROOT/pokemon_card_vault"
HOST="${POKOIN_CODEX_OBS_HOST:-oracle-peer1}"
WWW_ROOT=/var/www/pokoin-codex-obsidian
TOKEN_FILE="${POKOIN_CODEX_OBS_TOKEN_FILE:-$HOME/.config/pokoin/codex-obsidian-token}"
STAGING=/tmp/pokoin-codex-obsidian-pack

mkdir -p "$(dirname "$TOKEN_FILE")"

if [[ "${1:-}" == "--new-token" ]] || [[ ! -f "$TOKEN_FILE" ]]; then
  openssl rand -hex 12 > "$TOKEN_FILE"
  echo "New token written to $TOKEN_FILE"
fi
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

rm -rf "$STAGING" /tmp/pokoin-codex-obsidian-pack.zip
mkdir -p "$STAGING/vault" "$STAGING/playbook" "$STAGING/docs" "$STAGING/workflows" "$STAGING/memory"

# --- App collaborator entrypoints ---
cp "$ROOT/scripts/codex-obsidian-pack-README.md" "$STAGING/README.md"
cp "$ROOT/scripts/codex-obsidian-pack-AGENTS.md" "$STAGING/AGENTS.md"
cp "$ROOT/scripts/codex-obsidian-pack-APP_COLLABORATOR.md" "$STAGING/APP_COLLABORATOR.md"

# --- Memory (no secrets) ---
for f in architecture.md current-state.md decisions.md obsidian-documentation.md \
         cursor-to-codex-handoff.md secrets-workflow.md bugs-and-fixes.md; do
  [[ -f "$ROOT/memory/$f" ]] && cp "$ROOT/memory/$f" "$STAGING/memory/"
done

# --- Core API / app docs ---
DOC_FILES=(
  pokoin-api.md
  react-api-architecture.md
  react-page-apis.md
  marketplace-public-ids.md
  marketplace-search-ranking.md
  marketplace-card-image-pipeline.md
  extension-card-search-api.md
  common-user-actions.md
  firebase-data-model.md
  oracle-api-migration.md
  landing-root.md
  api-route-catalog.json
)
for f in "${DOC_FILES[@]}"; do
  [[ -f "$PCV/docs/$f" ]] && cp "$PCV/docs/$f" "$STAGING/docs/"
done
# optional contract json if present
[[ -f "$PCV/docs/react-api-contract.json" ]] && cp "$PCV/docs/react-api-contract.json" "$STAGING/docs/"
[[ -f "$ROOT/docs/react-api-architecture.md" ]] && cp "$ROOT/docs/react-api-architecture.md" "$STAGING/docs/react-api-architecture-root.md"
[[ -f "$ROOT/docs/react-page-apis.md" ]] && cp "$ROOT/docs/react-page-apis.md" "$STAGING/docs/react-page-apis-root.md"

# --- Workflows (operator playbooks; skip huge reports/) ---
WF_FILES=(
  README.md
  api-workflow.md
  pokoin-api-auth-workflow.md
  meilisearch-peer-workflow.md
  oracle-marketplace-postgres-workflow.md
  card-market-page-workflow.md
  pokoin-vercel-404-recovery-workflow.md
  limitless-competitive-workflow.md
  stripe-pokoin-checkout-workflow.md
  crypto-pkn-purchase-workflow.md
  pokontact-assistant-workflow.md
  prisma-oracle-workflow.md
  forum-workflow.md
  swap_bridge-workflow.md
  social-autoposter-workflow.md
  pokemon-card-extension-auth-and-cardmarket-api-handoff.md
)
for f in "${WF_FILES[@]}"; do
  [[ -f "$PCV/workflows/$f" ]] && cp "$PCV/workflows/$f" "$STAGING/workflows/"
done

# --- Obsidian playbook + Pi templates ---
cp "$ROOT/memory/obsidian-documentation.md" "$STAGING/playbook/"
scp -o BatchMode=yes 'pi-cursor:/home/nes/Obsidian/Pokoin/Templates/'*.md "$STAGING/playbook/" || true
scp -o BatchMode=yes 'pi-cursor:/home/nes/Obsidian/Templates/AI project vault notes.md' "$STAGING/playbook/" || true

# --- Obsidian vault snapshot ---
ssh -o BatchMode=yes pi-cursor 'cd /home/nes/Obsidian && tar --exclude="Pokoin/scripts" -czf /tmp/pokoin-obsidian-vault.tgz Pokoin'
scp -o BatchMode=yes pi-cursor:/tmp/pokoin-obsidian-vault.tgz /tmp/pokoin-obsidian-vault.tgz
tar -xzf /tmp/pokoin-obsidian-vault.tgz -C "$STAGING/vault"

(cd /tmp && zip -r -q pokoin-codex-obsidian-pack.zip pokoin-codex-obsidian-pack)

ssh -o BatchMode=yes "$HOST" "sudo mkdir -p $WWW_ROOT/$TOKEN && sudo chown -R ubuntu:ubuntu $WWW_ROOT"
rsync -az --delete "$STAGING/" "$HOST:$WWW_ROOT/$TOKEN/"
scp -o BatchMode=yes /tmp/pokoin-codex-obsidian-pack.zip "$HOST:$WWW_ROOT/$TOKEN/pokoin-codex-obsidian-pack.zip"

ssh -o BatchMode=yes "$HOST" "TOKEN=$TOKEN bash -s" <<'REMOTE'
ROOT=/var/www/pokoin-codex-obsidian/$TOKEN
cat > "$ROOT/index.html" <<EOF
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Pokoin Codex pack (app + API + Obsidian)</title>
<body>
<h1>Pokoin Codex pack</h1>
<p>For app collaborators (Flutter / React / APIs) and Codex.</p>
<p><a href="pokoin-codex-obsidian-pack.zip"><strong>Download zip</strong></a></p>
<ul>
  <li><a href="AGENTS.md">AGENTS.md</a> — read first</li>
  <li><a href="APP_COLLABORATOR.md">APP_COLLABORATOR.md</a> — Pi API + what you can do</li>
  <li><a href="docs/pokoin-api.md">docs/pokoin-api.md</a></li>
  <li><a href="docs/react-page-apis.md">docs/react-page-apis.md</a></li>
  <li><a href="docs/marketplace-public-ids.md">docs/marketplace-public-ids.md</a></li>
  <li><a href="workflows/README.md">workflows/README.md</a></li>
  <li><a href="playbook/obsidian-documentation.md">Obsidian playbook</a></li>
  <li><a href="README.md">README</a></li>
</ul>
</body>
</html>
EOF
REMOTE

URL="https://rpc.pokoin.com/codex-obsidian/$TOKEN/"
ZIP="${URL}pokoin-codex-obsidian-pack.zip"
echo "Published:"
echo "  $URL"
echo "  $ZIP"
ls -lh /tmp/pokoin-codex-obsidian-pack.zip
curl -fsSIL "$ZIP" | head -8
curl -fsS "${URL}APP_COLLABORATOR.md" | head -5
