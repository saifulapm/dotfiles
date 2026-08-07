#!/usr/bin/env bash
# Emacs 31 (the emacs-31 release branch — NOT master, which already
# identifies as 32.0.50) is the editor actually run — the emacs-pgtk rpm (30.2)
# stays as the /usr/bin fallback, the same two-tier shape as the Arch box
# (pacman emacs-wayland + rebuild-emacs). Built into ~/.local/bin, which
# PATH prefers, so emacs/emacsclient resolve to it everywhere; the daemon
# follows via the systemd drop-in rebuild-emacs writes. Guarded: only a
# machine with no local build pays the build; rolling forward is a manual
# `rebuild-emacs` — an apply must never surprise-rebuild the editor.
set -uo pipefail

warn() { echo "emacs-31: $*" >&2; }

[ -x "$HOME/.local/bin/emacs" ] && exit 0

rebuild="${CHEZMOI_WORKING_TREE:-$HOME/.dotfiles}/bin/rebuild-emacs"
[ -x "$rebuild" ] || { warn "bin/rebuild-emacs not found — skipping"; exit 0; }

echo "emacs-31: no local build — building emacs-31 (first run only, expect a long build)"
"$rebuild" \
  || warn "build failed or deps missing — run rebuild-emacs by hand for the log"
exit 0
