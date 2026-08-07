#!/usr/bin/env bash
# Never sleep (decision 2026-08-07): agentic sessions run for hours and Asahi
# never brings the display back after resume, so suspend is removed at every
# layer. A logind drop-in stops the lid and suspend/hibernate keys from
# suspending (lid close is niri switch-events: lock + screens off), and the
# sleep targets are masked so even a stray `systemctl suspend` is a no-op
# until unmasked. Lidless machines (Mac mini, NUC) get the same treatment —
# the drop-in is inert there and the masking is still wanted.
set -uo pipefail

conf=/etc/systemd/logind.conf.d/10-no-suspend.conf

if [ -f "$conf" ] && [ "$(systemctl is-enabled suspend.target 2>/dev/null)" = "masked" ]; then
  exit 0
fi

# Root, by whichever route this run can actually reach (same ladder as
# 01-autologin): cached sudo, interactive sudo when a terminal exists, then
# pkexec so a background apply can land this with on-screen approval.
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "no-suspend: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
# Managed by ~/.dotfiles (run_after_18-no-suspend.sh). Never suspend: Asahi
# resume leaves the display dead and long agentic jobs must keep the network
# up. Lid close is handled by niri switch-events (lock + screens off).
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
EOF
chmod 0644 "$tmp"

# One root call — a pkexec route prompts once per call, so the drop-in
# install, the logind config reload and the masking are combined.
if ! run_root /bin/sh -c "install -D -m 0644 '$tmp' '$conf' \
    && systemctl reload systemd-logind \
    && systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target"; then
  echo "no-suspend: not authorized — lid close still suspends (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi
echo "no-suspend: logind lid/suspend handling off, sleep targets masked"
