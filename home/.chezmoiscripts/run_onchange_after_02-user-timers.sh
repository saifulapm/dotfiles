#!/usr/bin/env bash
# Enable user units shipped in dot_config/systemd/user. Re-runs when this
# script changes; no sudo needed (user manager).
# unit-list: qshell-updates.timer taildrop-receive.service
set -euo pipefail

units=(qshell-updates.timer taildrop-receive.service)

if command -v systemctl >/dev/null && systemctl --user is-system-running >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now "${units[@]}"
  echo "user units: ${units[*]} enabled"
else
  echo "user units: no user systemd session, skipped" >&2
fi
