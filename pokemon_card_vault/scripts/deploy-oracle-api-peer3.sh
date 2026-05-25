#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_TARGET="${ORACLE_API_SSH_TARGET:-ubuntu@141.147.62.244}"
SSH_KEY="${ORACLE_API_SSH_KEY:-$HOME/pokoinpos/keys/peer3/ssh-key-2026-05-16.key}"
REMOTE_DIR="${ORACLE_API_REMOTE_DIR:-pokoin-oracle-api}"
REMOTE_PORT="${ORACLE_API_PORT:-18080}"
SERVICE_NAME="${ORACLE_API_SERVICE_NAME:-pokoin-oracle-api}"
DOCKER_IMAGE="${ORACLE_API_DOCKER_IMAGE:-node:20-bookworm}"
DOCKER_BIN="${ORACLE_API_DOCKER_BIN:-sudo docker}"
NO_RESTART=0

for arg in "$@"; do
  case "$arg" in
    --no-restart)
      NO_RESTART=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"
npm run api:docs
npm run api:check
ORACLE_API_BUNDLE_DIR="$ROOT_DIR/build/oracle-api" bash "$ROOT_DIR/scripts/package-oracle-api-service.sh"

archive="$ROOT_DIR/build/oracle-api.tgz"
tar -C "$ROOT_DIR/build/oracle-api" -czf "$archive" .

ssh_cmd=(ssh)
scp_cmd=(scp)
if [[ -n "$SSH_KEY" ]]; then
  ssh_cmd+=( -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new )
  scp_cmd+=( -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new )
fi

"${ssh_cmd[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR/releases'"
release_name="release-$(date +%Y%m%d%H%M%S)"
"${scp_cmd[@]}" "$archive" "$SSH_TARGET:$REMOTE_DIR/releases/$release_name.tgz"
"${ssh_cmd[@]}" "$SSH_TARGET" "set -euo pipefail; mkdir -p '$REMOTE_DIR/releases/$release_name'; tar -xzf '$REMOTE_DIR/releases/$release_name.tgz' -C '$REMOTE_DIR/releases/$release_name'; ln -sfn 'releases/$release_name' '$REMOTE_DIR/current'; $DOCKER_BIN run --rm -v \"\$PWD/$REMOTE_DIR/current:/app\" -w /app '$DOCKER_IMAGE' npm ci --omit=dev"

if [[ "$NO_RESTART" == "1" ]]; then
  echo "Uploaded Oracle API service to $SSH_TARGET:$REMOTE_DIR/current"
  echo "Restart skipped. Start on peer3 with: cd '$REMOTE_DIR/current' && PORT=$REMOTE_PORT npm run api:server"
  exit 0
fi

"${ssh_cmd[@]}" "$SSH_TARGET" "set -euo pipefail; $DOCKER_BIN rm -f '$SERVICE_NAME' >/dev/null 2>&1 || true; $DOCKER_BIN run -d --name '$SERVICE_NAME' --restart unless-stopped --env-file '$REMOTE_DIR/.env' -e PORT='$REMOTE_PORT' -p 127.0.0.1:$REMOTE_PORT:$REMOTE_PORT -v \"\$PWD/$REMOTE_DIR/current:/app\" -w /app '$DOCKER_IMAGE' node server/oracle-api-server.js"

echo "Deployed Oracle API service to $SSH_TARGET:$REMOTE_DIR/current as $SERVICE_NAME on port $REMOTE_PORT"
