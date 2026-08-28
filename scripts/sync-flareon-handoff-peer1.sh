#!/usr/bin/env bash
set -euo pipefail

# Copy Pokoin Cursor summary for Flareon (no secrets, no code).
# Target on peer1: /opt/hermes-flareon/data/pokoin-handoff.md

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="${ROOT}/memory/flareon-handoff.md"
HERMES_SCRIPTS="${HERMES_SCRIPTS:-$HOME/Hermes/scripts}"

if [[ ! -f "$HANDOFF" ]]; then
  echo "Missing $HANDOFF" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$HERMES_SCRIPTS/flareon-secrets.sh"
KEY="$(flareon_resolve_peer1_key)"
HOST="${FLAREON_PEER1_HOST:-92.5.153.117}"
USER="${FLAREON_PEER1_USER:-ubuntu}"
REMOTE_PATH="/opt/hermes-flareon/data/pokoin-handoff.md"

echo "Syncing Flareon handoff ($(wc -c <"$HANDOFF" | tr -d ' ') bytes) to ${USER}@${HOST}:${REMOTE_PATH}"
ssh -i "$KEY" "${USER}@${HOST}" "sudo mkdir -p /opt/hermes-flareon/data"
scp -i "$KEY" "$HANDOFF" "${USER}@${HOST}:/tmp/pokoin-handoff.md"
ssh -i "$KEY" "${USER}@${HOST}" "sudo mv /tmp/pokoin-handoff.md ${REMOTE_PATH} && sudo chmod 644 ${REMOTE_PATH}"
echo "Done. Flareon loads this on the next reply (see FLAREON_POKOIN_HANDOFF_PATH on peer1)."
