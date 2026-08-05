#!/usr/bin/env bash
# Enable user timers shipped in dot_config/systemd/user. Re-runs when this
# script changes; no sudo needed (user manager).
# timer-list: qshell-updates.timer
set -euo pipefail

if command -v systemctl >/dev/null && systemctl --user is-system-running >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now qshell-updates.timer
  echo "user timers: qshell-updates.timer enabled"
else
  echo "user timers: no user systemd session, skipped" >&2
fi
