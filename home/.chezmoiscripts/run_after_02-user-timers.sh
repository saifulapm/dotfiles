#!/usr/bin/env bash
# Enable user units shipped in dot_config/systemd/user, plus packaged ones we
# opt into (foot-server.socket, from the foot rpm: socket activation per
# foot(1) — enable ONLY the socket; the first footclient connect starts the
# server, and a crashed server restarts on the next connect). Runs on every
# apply (enable --now on an enabled unit is a cheap no-op); no sudo needed
# (user manager). Was run_onchange, but a run that skipped — no user session,
# or the old degraded-state bug below — was recorded as done and never retried.
# unit-list: qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service foot-server.socket ssh-agent.socket udiskie.service voxtype-idle-stop.timer clipboard-serve.socket qshell.service emacs.service mempressure.service clipboard-sync.service
# Also DISABLES voxtype.service — see the block near the end of this file.
set -euo pipefail

# ssh-agent.socket: Fedora's packaged agent unit — socket activation, so
# enabling costs nothing until the first ssh; SSH_AUTH_SOCK pointing at it
# comes from environment.d/65-ssh-agent.conf.
# udiskie.service is ConditionPathExists-gated on its binary, so enabling it
# before the udiskie package lands is a clean no-op, not a failed unit.
# voxtype-idle-stop.timer stops the dictation daemon once it has sat idle; it
# is safe to enable on a machine with no voxtype at all, since the script it
# runs exits immediately when the daemon's runtime state file is absent.
# clipboard-serve.socket is loopback-only per-connection activation
# (bin/clipboard-serve); enabling it needs no session — a request arriving
# outside one just answers empty/500 and the socket stays healthy.
units=(qshell-updates.timer taildrop-receive.service qshell-sync.timer bt-agent.service foot-server.socket ssh-agent.socket udiskie.service voxtype-idle-stop.timer clipboard-serve.socket)

# is-system-running exits nonzero for "degraded" (= any ONE user unit has
# failed), which is not "no user session" — treating it that way silently
# skipped enabling these units on a machine with one unrelated failed unit
# (found 2026-08-06: a failed xdg-desktop-portal-gtk.service was enough).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  # Guarded like everything below (audit 2026-08-08): these three were bare
  # under set -e, and a qshell crash-looped into start-limit aborted the
  # apply here — silently skipping scripts 03-99 on every rerun.
  systemctl --user daemon-reload \
    || echo "user units: daemon-reload failed" >&2
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
  # mempressure.service (PSI early-warning, needs the notification daemon)
  # shares qshell's Requisite gate and rides the same enable/start split.
  # clipboard-sync.service (wl-paste watcher pushing copies to the other
  # machines) needs the Wayland socket, so it rides it too.
  systemctl --user enable qshell.service mempressure.service clipboard-sync.service \
    || echo "user units: enable qshell/mempressure/clipboard-sync failed — check systemctl --user status qshell.service mempressure.service clipboard-sync.service" >&2
  if systemctl --user -q is-active graphical-session.target; then
    systemctl --user start qshell.service mempressure.service clipboard-sync.service \
      || echo "user units: start qshell/mempressure/clipboard-sync failed — check systemctl --user status qshell.service mempressure.service clipboard-sync.service" >&2
  fi
  echo "user units: qshell.service mempressure.service clipboard-sync.service enabled"
  # emacs.service (ours — shadows the emacs-pgtk rpm unit) has the same
  # Requisite=graphical-session.target gate: enable always, start only
  # inside a session. --no-block because a first start bootstraps every
  # :ensure package (minutes) and the apply must not hang on it;
  # warn-don't-abort like the loop above.
  systemctl --user enable emacs.service 2>/dev/null \
    || echo "user units: enable emacs.service failed — check systemctl --user status emacs.service" >&2
  if systemctl --user -q is-active graphical-session.target; then
    systemctl --user start --no-block emacs.service 2>/dev/null \
      || echo "user units: start emacs.service failed — check systemctl --user status emacs.service" >&2
  fi
  echo "user units: emacs.service enabled"
  # voxtype.service is the one unit here that must be OFF. Its daemon PRELOADS
  # the whisper model rather than loading it per utterance — 486 MB resident
  # for small.en, measured — so leaving it enabled parks half a gigabyte on a
  # 7.3 GB laptop to do nothing (it burns no CPU idle; this is purely RAM).
  # bin/voxtype-toggle, which the niri binds spawn, starts it on the keypress
  # in ~0.2 s instead, and voxtype-idle-stop.timer above stops it again after
  # 10 min idle. Numbers and reasoning in packages/manifest.toml.
  #
  # Guarded on the unit existing: voxtype is a hand install (`voxtype setup
  # systemd` writes this unit, nothing in this repo does), so it is legitimately
  # absent on a fresh machine and `disable` would otherwise warn every apply.
  #
  # DISABLE ONLY, never stop. `disable` is what keeps the next login from
  # starting it; stopping a RUNNING one is the idle timer's job precisely
  # because that script checks the daemon's state first and refuses to act
  # mid-recording. A blind `systemctl stop` here would cut off a dictation in
  # progress during an apply.
  if systemctl --user cat voxtype.service >/dev/null 2>&1; then
    systemctl --user disable voxtype.service >/dev/null 2>&1 \
      || echo "user units: disable voxtype.service failed — check systemctl --user status voxtype.service" >&2
    echo "user units: voxtype.service disabled (on-demand via bin/voxtype-toggle)"
  fi
else
  echo "user units: no user systemd session, skipped" >&2
fi
