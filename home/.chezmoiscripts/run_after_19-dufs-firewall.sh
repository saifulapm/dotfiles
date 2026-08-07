#!/usr/bin/env bash
# Open TCP 5000 for dufs (decision 2026-08-07): the phone-over-LAN file
# server's gate is its off-by-default unit plus basic auth, not the firewall —
# but every machine runs firewalld with a default zone that drops unsolicited
# ports, so the widget's LAN URL was dead until this. No --zone: the port is
# added to whatever the machine's default zone is (public on Asahi and the
# NUC's minimal install).
set -uo pipefail

command -v firewall-cmd >/dev/null 2>&1 || exit 0
systemctl is-active --quiet firewalld 2>/dev/null || exit 0

# Runtime query is polkit-allowed for an active session ("yes"/"no" by exit
# code) — good enough as the guard since this script is what sets both halves.
if firewall-cmd --query-port=5000/tcp >/dev/null 2>&1; then
  exit 0
fi

# Root, by whichever route this run can actually reach (same ladder as
# 18-no-suspend): cached sudo, interactive sudo when a terminal exists, then
# pkexec so a background apply can land this with on-screen approval.
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "dufs-firewall: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

# One root call — a pkexec route prompts once per call, so the runtime and
# permanent halves are combined.
if ! run_root /bin/sh -c "firewall-cmd --quiet --add-port=5000/tcp \
    && firewall-cmd --quiet --permanent --add-port=5000/tcp"; then
  echo "dufs-firewall: not authorized — LAN port 5000 stays closed (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi
echo "dufs-firewall: TCP 5000 open (runtime + permanent) for dufs"
