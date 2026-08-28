#!/usr/bin/env bash
set -euo pipefail

MEILI_VERSION="${MEILI_VERSION:-v1.10.3}"
MEILI_USER="${MEILI_USER:-meili}"
MEILI_GROUP="${MEILI_GROUP:-meili}"
MEILI_INSTALL_DIR="${MEILI_INSTALL_DIR:-/opt/meilisearch}"
MEILI_STATE_DIR="${MEILI_STATE_DIR:-/var/lib/meilisearch}"
MEILI_CONFIG_DIR="${MEILI_CONFIG_DIR:-/etc/pokemon-card-vault}"
SERVICE_NAME="${SERVICE_NAME:-meilisearch}"

echo "[1/7] Creating meili user/group if missing"
if ! getent group "${MEILI_GROUP}" >/dev/null; then
  sudo groupadd --system "${MEILI_GROUP}"
fi
if ! id -u "${MEILI_USER}" >/dev/null 2>&1; then
  sudo useradd --system --gid "${MEILI_GROUP}" --home "${MEILI_INSTALL_DIR}" --shell /usr/sbin/nologin "${MEILI_USER}"
fi

echo "[2/7] Creating directories"
sudo mkdir -p "${MEILI_INSTALL_DIR}" "${MEILI_STATE_DIR}/data.ms" "${MEILI_STATE_DIR}/dumps" "${MEILI_STATE_DIR}/snapshots" "${MEILI_CONFIG_DIR}"
sudo chown -R "${MEILI_USER}:${MEILI_GROUP}" "${MEILI_INSTALL_DIR}" "${MEILI_STATE_DIR}"

echo "[3/7] Installing meilisearch binary"
curl -fsSL "https://github.com/meilisearch/meilisearch/releases/download/${MEILI_VERSION}/meilisearch-linux-amd64" -o /tmp/meilisearch
chmod +x /tmp/meilisearch
sudo mv /tmp/meilisearch /usr/local/bin/meilisearch

echo "[4/7] Installing config templates"
sudo cp deploy/meili/meili.toml.example "${MEILI_CONFIG_DIR}/meili.toml"
if [[ ! -f "${MEILI_CONFIG_DIR}/meili.env" ]]; then
  cat <<'EOF' | sudo tee "${MEILI_CONFIG_DIR}/meili.env" >/dev/null
MEILI_MASTER_KEY=replace-with-long-random-key
EOF
fi
sudo chown root:root "${MEILI_CONFIG_DIR}/meili.toml" "${MEILI_CONFIG_DIR}/meili.env"
sudo chmod 600 "${MEILI_CONFIG_DIR}/meili.env"

echo "[5/7] Installing systemd service"
sudo cp deploy/meili/meilisearch.service "/etc/systemd/system/${SERVICE_NAME}.service"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"

echo "[6/7] Starting service"
sudo systemctl restart "${SERVICE_NAME}"
sleep 2

echo "[7/7] Verifying health"
curl -fsS "http://127.0.0.1:7700/health" | sed 's/.*/meili health: &/'
sudo systemctl --no-pager --full status "${SERVICE_NAME}" | sed -n '1,15p'

echo "Install complete."
