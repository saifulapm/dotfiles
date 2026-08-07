#!/usr/bin/env bash
# Enable user units shipped in dot_config/systemd/user, plus packaged ones we
# opt into (foot-server.socket, from the foot rpm: socket activation per
# foot(1) — enable ONLY the socket; the first footclient connect starts the
# server, and a crashed server restarts on the next connect). Runs on every
# apply (enable --now on an enabled unit is a cheap no-op); no sudo needed
# (user manager). Was run_onchange, but a run that skipped — no user session,
# or the old degraded-state bug below — was recorded as done and never retried.
# unit-list: qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service foot-server.socket qshell.service
set -euo pipefail

units=(qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service foot-server.socket)

# is-system-running exits nonzero for "degraded" (= any ONE user unit has
# failed), which is not "no user session" — treating it that way silently
# skipped enabling these units on a machine with one unrelated failed unit
# (found 2026-08-06: a failed xdg-desktop-portal-gtk.service was enough).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  systemctl --user daemon-reload
  # Per unit, warn-don't-abort: one unit failing to start must not abort the
  # apply (set -e) or keep the remaining units from being enabled.
  for unit in "${units[@]}"; do
    systemctl --user enable --now "$unit" 2>/dev/null \
      || echo "user units: enable --now $unit failed — check systemctl --user status $unit" >&2
  done
  echo "user units: ${units[*]} enabled"
  # The shell is Requisite=graphical-session.target, so `enable --now` with
  # the others would fail the whole script on a TTY-only apply: enable it
  # always, start it only when a graphical session is actually up (a no-op
  # when it is already running).
  systemctl --user enable qshell.service
  if systemctl --user -q is-active graphical-session.target; then
    systemctl --user start qshell.service
  fi
  echo "user units: qshell.service enabled"
else
  echo "user units: no user systemd session, skipped" >&2
fi
