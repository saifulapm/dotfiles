#!/usr/bin/env bash
# libinput-gestures (github.com/bulletmark/libinput-gestures) — the touchpad
# gestures niri has no way to bind. niri implements three-finger swipes and
# the four-finger overview internally and offers no gesture-binding syntax at
# all (upstream #372, open, "needs design"), so the macOS-style Launchpad and
# Notification Centre pinches come from this daemon instead. What it binds,
# and why every binding is a pinch rather than a swipe, is documented in
# home/dot_config/libinput-gestures.conf.
#
# Not a dnf package: it is packaged for neither Fedora nor any COPR (checked
# 2026-08-18), so it rides the same user checkout shape as nirisaver and
# nirisnap — ~/.local/src for the clone, ~/.local/bin for the program, and an
# update-all `update_src` line that deletes the program to force a reinstall
# when upstream moves. Guarded, warn-don't-abort.
#
# Nothing here needs root. Upstream's own installer wants `sudo make install`
# into /usr/bin and /etc; this installs only the one script it actually runs,
# and the program searches (XDG_CONFIG_HOME, /etc) for its config in that
# order, so this repo's ~/.config/libinput-gestures.conf wins with no system
# file present at all. Its unit is ours too (dot_config/systemd/user), not
# the /usr/bin-hardcoded one upstream ships.
set -uo pipefail

warn() { echo "libinput-gestures: $*" >&2; }

src="$HOME/.local/src/libinput-gestures"
out="$HOME/.local/bin/libinput-gestures"

if [ ! -x "$out" ]; then
  command -v python3 >/dev/null 2>&1 || {
    warn "python3 missing — skipping"
    exit 0
  }
  # It drives `libinput debug-events`; without the CLI it starts and then
  # does nothing forever, which is worse than not installing it.
  command -v libinput >/dev/null 2>&1 || {
    warn "libinput CLI missing — skipping"
    exit 0
  }

  # rev-parse, not [ -d .git ]: a clone killed mid-transfer must not satisfy
  # the check forever (same guard as nirisaver and the kakoune fork).
  if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
    rm -rf "$src"
    mkdir -p "$HOME/.local/src"
    git clone --depth 1 https://github.com/bulletmark/libinput-gestures "$src" \
      || { warn "clone failed"; exit 0; }
  fi

  mkdir -p "$HOME/.local/bin"
  install -m755 "$src/libinput-gestures" "$out" \
    && echo "libinput-gestures: installed to ~/.local/bin/libinput-gestures" \
    || { warn "install failed"; exit 0; }
fi

# input group: needed to read /dev/input/event*. Same sudo->pkexec ladder as
# run_after_34-dshift, which needs it for the same reason. Warn-don't-abort;
# the service sits in restart-backoff until access exists, then recovers.
# `case` rather than `id -nG | grep -qx`: grep exiting early SIGPIPEs the
# upstream process, and under `set -o pipefail` that reads as a failure.
case ":$(id -nG | tr ' ' ':'):" in
  *:input:*) ;;
  *)
    grant() { "$@" usermod -aG input "$USER"; }
    if sudo -n true 2>/dev/null; then
      grant sudo -n || true
    elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v pkexec >/dev/null 2>&1; then
      grant pkexec || true
    fi
    if getent group input | grep -q "\b$USER\b"; then
      echo "libinput-gestures: added to input group (takes effect at next login)"
      # Same-session bridge: ACLs apply immediately and by uid, so the daemon
      # can start now rather than after a relogin. Gone at reboot; the group
      # membership carries it from then on.
      setfacl -m "u:$USER:r" /dev/input/event* 2>/dev/null || true
    else
      warn "could not join input group — run: sudo usermod -aG input $USER"
    fi
    ;;
esac

# Enable always; start only inside a graphical session (the unit is
# Requisite=graphical-session.target — run_after_02's qshell.service split).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  systemctl --user daemon-reload || true
  systemctl --user enable libinput-gestures.service 2>/dev/null \
    || warn "enable libinput-gestures.service failed"
  if systemctl --user -q is-active graphical-session.target; then
    systemctl --user restart libinput-gestures.service 2>/dev/null \
      || warn "start failed — check systemctl --user status libinput-gestures"
  fi
  echo "libinput-gestures: libinput-gestures.service enabled"
fi

exit 0
