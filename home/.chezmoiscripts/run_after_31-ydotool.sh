#!/usr/bin/env bash
# ydotool for the desktop skill (decision 2026-08-11): the one human input
# action Wayland's virtual-pointer CLI cannot express is holding a button
# down across a move — drag-and-drop, sliders, marquee selection. wlrctl
# stays the default pointer (no daemon, no uinput); ydotool exists for the
# drag case and for absolute positioning, and reaches XWayland too.
#
# Two things are needed and neither is a package's job: /dev/uinput is
# root-only by default (a udev rule hands it to the `input` group), and
# ydotool talks to a resident ydotoold. The daemon runs as a USER service —
# it only needs the device node, so nothing here runs as root at runtime.
set -uo pipefail

command -v ydotool >/dev/null 2>&1 || exit 0   # not installed: nothing to wire

rule=/etc/udev/rules.d/60-uinput-input-group.rules
unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/ydotoold.service"

wired=0
[ -f "$rule" ] && id -nG | tr ' ' '\n' | grep -qx input && wired=1
[ "$wired" = 1 ] && [ -f "$unit" ] &&
  systemctl --user is-enabled ydotoold.service >/dev/null 2>&1 && exit 0

# Root by whichever route this run can reach (same ladder as 18-no-suspend).
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "ydotool: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

if [ ! -f "$rule" ]; then
  tmp=$(mktemp)
  cat >"$tmp" <<'RULE'
# /dev/uinput to the input group so ydotoold can run as the user, not root.
# Managed by ~/.dotfiles (run_after_31-ydotool.sh).
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
RULE
  if run_root install -m 0644 "$tmp" "$rule"; then
    run_root udevadm control --reload-rules
    run_root udevadm trigger --name-match=uinput
  else
    echo "ydotool: could not write $rule — drag support stays off" >&2
  fi
  rm -f "$tmp"
fi

id -nG | tr ' ' '\n' | grep -qx input ||
  run_root usermod -aG input "$USER" ||
  echo "ydotool: could not add $USER to the input group" >&2

mkdir -p "$(dirname "$unit")"
cat >"$unit" <<'UNIT'
[Unit]
Description=ydotoold — virtual input device for drag-capable pointer control
Documentation=man:ydotoold(8)

[Service]
# The socket lives under the user runtime dir; ydotool finds it via
# $YDOTOOL_SOCKET, exported in the shell profile.
ExecStart=/usr/bin/ydotoold --socket-path=%t/.ydotool_socket --socket-own=%U:%G
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable ydotoold.service 2>/dev/null

# Starting it now only works if this session already carries the `input`
# group: a user manager that was started before `usermod` keeps the old
# supplementary groups, and the daemon dies with "failed to open uinput
# device: Permission denied" (observed 2026-08-11). Enabling is enough —
# the next login starts it with the right groups. `/usr/bin/sg input -c
# 'ydotoold …'` is the same-session workaround if it is wanted sooner.
if id -nG | tr ' ' '\n' | grep -qx input; then
  systemctl --user start ydotoold.service 2>/dev/null ||
    echo "ydotool: ydotoold failed to start — check journalctl --user -u ydotoold" >&2
else
  echo "ydotool: wired; ydotoold starts at your next login (input group)" >&2
fi
