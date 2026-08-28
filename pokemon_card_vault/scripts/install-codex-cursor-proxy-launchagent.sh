#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.pokoin.codex-cursor-proxy"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs"
START_SCRIPT="${ROOT}/scripts/start-codex-cursor-proxy.sh"

mkdir -p "${HOME}/Library/LaunchAgents" "${LOG_DIR}"

cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${START_SCRIPT}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${HOME}/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>

  <key>WorkingDirectory</key>
  <string>${ROOT}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${LOG_DIR}/codex-cursor-proxy.log</string>

  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/codex-cursor-proxy.error.log</string>
</dict>
</plist>
EOF

plutil -lint "${PLIST_PATH}" >/dev/null
launchctl bootout "gui/$(id -u)" "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
launchctl enable "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true

echo "Installed and started ${LABEL}"
echo "Logs: ${LOG_DIR}/codex-cursor-proxy.log"
