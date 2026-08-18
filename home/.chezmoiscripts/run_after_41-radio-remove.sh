#!/usr/bin/env bash
# Sweeps up after bin/radio and bin/music, replaced by cliamp on 2026-08-18.
#
# Deleting a file from the source state does NOT delete the copy in $HOME:
# chezmoi stops managing it and walks away, which in symlink mode leaves a
# DANGLING symlink pointing at a repo path that no longer exists. Two of those
# were left behind here, and a dangling completion file is not inert — fish
# sources ~/.config/fish/completions on every prompt and would keep offering
# `radio` subcommands for a command that is gone.
#
# run_after_, not run_once_after_, for the reason run_after_39 spells out: a
# run_once_ script is recorded as done the first time it runs, and the other
# machines have not applied this yet. The guards below ARE the state — this
# costs two `test -L` per apply and disarms itself once both are gone.
#
# Every removal is guarded on the path being a SYMLINK whose target does not
# resolve. A real file at either path is somebody's deliberate replacement and
# is left exactly where it is.
set -uo pipefail

removed=0

# -L and not -e: a symlink whose target is missing. Together those are the
# precise signature of "chezmoi used to manage this and the source is gone".
for stale in \
  "$HOME/.config/fish/completions/radio.fish" \
  "$HOME/.config/qshell/radio-stations"; do
  if [ -L "$stale" ] && [ ! -e "$stale" ]; then
    rm -f "$stale" && removed=$((removed + 1))
  fi
done

# bin/radio's state file — the station it was last told to play. Never managed
# by chezmoi, so nothing else will ever clean it up. Absent on this machine
# already; the other two have not applied yet.
if [ -f "$HOME/.local/state/qshell/radio" ]; then
  rm -f "$HOME/.local/state/qshell/radio" && removed=$((removed + 1))
fi

# The fixed unit bin/radio streamed under. Transient, so it disappears on its
# own once stopped — but a machine that is mid-stream when it applies this
# would otherwise keep playing with no script left to stop it.
if systemctl --user is-active --quiet qshell-radio.service 2>/dev/null; then
  systemctl --user stop qshell-radio.service 2>/dev/null \
    && echo "radio-remove: stopped a stream still playing under qshell-radio.service"
fi

[ "$removed" -gt 0 ] && echo "radio-remove: cleared $removed leftover(s) from the old radio stack"

exit 0
