#!/usr/bin/env bash
# Enable user units shipped in dot_config/systemd/user. Runs on every apply
# (enable --now on an enabled unit is a cheap no-op); no sudo needed (user
# manager). Was run_onchange, but a run that skipped — no user session, or
# the old degraded-state bug below — was recorded as done and never retried.
# unit-list: qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service
set -euo pipefail

units=(qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service)

# is-system-running exits nonzero for "degraded" (= any ONE user unit has
# failed), which is not "no user session" — treating it that way silently
# skipped enabling these units on a machine with one unrelated failed unit
# (found 2026-08-06: a failed xdg-desktop-portal-gtk.service was enough).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  systemctl --user daemon-reload
  systemctl --user enable --now "${units[@]}"
  echo "user units: ${units[*]} enabled"
else
  echo "user units: no user systemd session, skipped" >&2
fi
