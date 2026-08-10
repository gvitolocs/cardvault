#!/usr/bin/env bash
# nespc only (192.168.178.25): update Cursor, then reboot this machine.
# Run on nespc itself (local shell or local Cursor agent). Do not run from a cloud agent.
#
# Usage:
#   ./workflows/nespc-update-cursor-and-reboot.sh
#   ./workflows/nespc-update-cursor-and-reboot.sh --dry-run

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

echo "== host guard =="
hostname
uname -a
whoami
ip -4 addr show 2>/dev/null | grep -F '192.168.178.25' || true

# Soft guard: prefer refusing unless this looks like nespc / has the LAN IP.
HOST="$(hostname -s 2>/dev/null || hostname)"
if [[ "${NESPC_FORCE:-}" != "1" ]]; then
  if [[ ! "$HOST" =~ [Nn]espc ]] && ! ip -4 addr 2>/dev/null | grep -qF '192.168.178.25'; then
    echo "Refusing: this does not look like nespc (hostname=$HOST)."
    echo "Re-run with NESPC_FORCE=1 only if you are sure this is the right machine."
    exit 1
  fi
fi

echo "== Cursor update =="
if command -v cursor >/dev/null 2>&1; then
  cursor --version || true
fi

if dpkg -l cursor 2>/dev/null | grep -q '^ii'; then
  run sudo apt-get update
  run sudo apt-get install -y --only-upgrade cursor
elif snap list cursor >/dev/null 2>&1; then
  run sudo snap refresh cursor
elif [[ -x /opt/cursor/cursor.AppImage || -x /opt/cursor/Cursor.AppImage ]]; then
  echo "AppImage install: clearing stuck pending updater state, then reboot."
  run rm -rf "${HOME}/.config/Cursor/pending" "${HOME}/.config/Cursor/updates"
  echo "After reboot, open Cursor once (or replace AppImage from https://cursor.com/download)."
else
  echo "Cursor package not found via apt/snap; clearing pending updater state anyway."
  run rm -rf "${HOME}/.config/Cursor/pending" "${HOME}/.config/Cursor/updates"
fi

echo "== reboot required flag =="
if [[ -f /var/run/reboot-required ]]; then
  echo "YES: /var/run/reboot-required present"
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
  echo "No /var/run/reboot-required flag (still rebooting nespc as requested)."
fi
if command -v needrestart >/dev/null 2>&1; then
  run sudo needrestart -b || true
fi

echo "== A1 hunt (informational) =="
HUNT_PID_FILE="${HOME}/secrets/deploy/oci-free-stack/a1-hunt.pid"
HUNT_SCRIPT="${HOME}/secrets/deploy/oci-free-stack/scripts/oci-a1-capacity-hunt.sh"
if [[ -f "$HUNT_PID_FILE" ]]; then
  pid="$(cat "$HUNT_PID_FILE" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    echo "A1 hunt running (pid ${pid}) — it will die across reboot; restart after:"
    echo "  ${HUNT_SCRIPT}"
  else
    echo "A1 hunt not running. After reboot, start if needed:"
    echo "  ${HUNT_SCRIPT}"
  fi
else
  echo "No A1 hunt pid file at ${HUNT_PID_FILE}"
fi

echo "== rebooting nespc =="
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN: sudo reboot"
  exit 0
fi
sudo reboot
