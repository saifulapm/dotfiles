#!/usr/bin/env bash
# Build the double-Shift capture watcher (packages/src/qshell-dshift.c →
# ~/.local/bin/qshell-dshift) and enable its user unit. The watcher reads
# /dev/input, so the user needs the `input` group — granted here through
# the sudo→pkexec ladder the other system touches use; group membership
# only lands at the NEXT login, so a same-session setfacl covers the gap.
# Rebuild is mtime-gated: a no-change apply costs one stat.
set -euo pipefail

src="$CHEZMOI_WORKING_TREE/packages/src/qshell-dshift.c"
out="$HOME/.local/bin/qshell-dshift"

if ! command -v gcc >/dev/null 2>&1; then
  echo "dshift: gcc not found — watcher not built (rerun chezmoi apply after the dnf half lands)" >&2
  exit 0
fi

if [ ! -e "$out" ] || [ "$src" -nt "$out" ]; then
  mkdir -p "$HOME/.local/bin"
  if gcc -O2 -Wall -o "$out" "$src"; then
    echo "dshift: built $out"
  else
    echo "dshift: build failed — double-Shift capture unavailable" >&2
    exit 0
  fi
fi

# input group: needed to read /dev/input/event*. Warn-don't-abort; the
# service will sit in restart-backoff until access exists, then recover.
if ! id -nG | tr ' ' '\n' | grep -qx input; then
  grant() { "$@" usermod -aG input "$USER"; }
  if sudo -n true 2>/dev/null; then
    grant sudo -n || true
  elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v pkexec >/dev/null 2>&1; then
    grant pkexec || true
  fi
  if id -nG | tr ' ' '\n' | grep -qx input || getent group input | grep -q "\b$USER\b"; then
    echo "dshift: added to input group (takes effect at next login)"
    # Same-session bridge: ACLs work immediately and by uid, so the service
    # can start now instead of after a relogin. Gone after reboot; the
    # group carries it from then on.
    setfacl -m "u:$USER:r" /dev/input/event* 2>/dev/null || true
  else
    echo "dshift: could not join input group — run: sudo usermod -aG input $USER" >&2
  fi
fi

# Enable always; start only inside a graphical session (the unit is
# Requisite=graphical-session.target — run_after_02's qshell.service split).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  systemctl --user daemon-reload || true
  systemctl --user enable qshell-dshift.service 2>/dev/null \
    || echo "dshift: enable qshell-dshift.service failed" >&2
  if systemctl --user -q is-active graphical-session.target; then
    systemctl --user restart qshell-dshift.service 2>/dev/null \
      || echo "dshift: start failed — check systemctl --user status qshell-dshift" >&2
  fi
  echo "dshift: qshell-dshift.service enabled"
fi
