#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/integrations/trainingai-oracle-api"

SSH_TARGET="${TRAININGAI_ORACLE_SSH_TARGET:-${ORACLE_API_SSH_TARGET:-ubuntu@141.147.62.244}}"
SSH_KEY="${TRAININGAI_ORACLE_SSH_KEY:-${ORACLE_API_SSH_KEY:-$HOME/pokoinpos/keys/peer3/ssh-key-2026-05-16.key}}"
REMOTE_DIR="${TRAININGAI_ORACLE_REMOTE_DIR:-/opt/trainingai-card-classifier}"
REMOTE_PORT="${TRAININGAI_ORACLE_PORT:-17860}"
SERVICE_NAME="${TRAININGAI_ORACLE_SERVICE_NAME:-pokoin-trainingai-card-classifier}"
DOCKER_BIN="${TRAININGAI_ORACLE_DOCKER_BIN:-sudo docker}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing Oracle classifier app directory: $APP_DIR" >&2
  exit 1
fi

ssh_cmd=(ssh)
scp_cmd=(scp)
if [[ -n "$SSH_KEY" ]]; then
  ssh_cmd+=( -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new )
  scp_cmd+=( -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new )
fi

tmp_archive="$(mktemp -t trainingai-oracle-api.XXXXXX.tgz)"
trap 'rm -f "$tmp_archive"' EXIT

tar -C "$APP_DIR" -czf "$tmp_archive" .

"${ssh_cmd[@]}" "$SSH_TARGET" "set -euo pipefail; sudo mkdir -p '$REMOTE_DIR/app' '$REMOTE_DIR/data'; sudo chown -R \"\$(id -u):\$(id -g)\" '$REMOTE_DIR'"
"${scp_cmd[@]}" "$tmp_archive" "$SSH_TARGET:$REMOTE_DIR/app.tgz"
"${ssh_cmd[@]}" "$SSH_TARGET" "set -euo pipefail; rm -rf '$REMOTE_DIR/app'; mkdir -p '$REMOTE_DIR/app'; tar -xzf '$REMOTE_DIR/app.tgz' -C '$REMOTE_DIR/app'; cd '$REMOTE_DIR/app'; $DOCKER_BIN build -t '$SERVICE_NAME' .; $DOCKER_BIN rm -f '$SERVICE_NAME' >/dev/null 2>&1 || true; touch '$REMOTE_DIR/.env'; $DOCKER_BIN run -d --name '$SERVICE_NAME' --restart unless-stopped --env-file '$REMOTE_DIR/.env' -e PORT=7860 -p 127.0.0.1:$REMOTE_PORT:7860 -v '$REMOTE_DIR/data:/opt/trainingai-card-classifier/data' '$SERVICE_NAME'"

echo "Deployed $SERVICE_NAME to $SSH_TARGET on 127.0.0.1:$REMOTE_PORT"
echo "Health check on the VM: curl -fsS http://127.0.0.1:$REMOTE_PORT/health"
