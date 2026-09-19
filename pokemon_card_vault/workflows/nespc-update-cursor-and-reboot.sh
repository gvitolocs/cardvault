#!/usr/bin/env bash
# DISABLED 2026-08-10: was causing reboot loop (apt upgrade cursor + sudo reboot).
# Restore from .bak-rebootloop-20260810 when safe.
echo "BLOCKED: nespc-update-cursor-and-reboot.sh disabled to stop reboot loop." >&2
exit 99
