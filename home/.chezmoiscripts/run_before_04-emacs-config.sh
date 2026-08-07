#!/usr/bin/env bash
# The Emacs config is its own living repo (github.com/saifulapm/emacs.d),
# edited and pushed from ~/.config/emacs — NOT chezmoi-managed, so this
# clones only when missing and never pulls (an auto-pull would rebase WIP
# out from under the editor; updates are plain git in that repo).
# ~/.config/emacs is where Emacs looks when ~/.emacs.d is absent (XDG —
# same location the Arch machine used). https clone so a fresh box needs
# no SSH key; flip to git@ for pushing after ~/.ssh lands (README, What
# stays manual). run_before rather than run_after so the config exists
# before run_after_02 starts emacs.service on a first apply — otherwise
# the daemon comes up configless and stays that way until a restart.
set -uo pipefail

warn() { echo "emacs-config: $*" >&2; }

dst="$HOME/.config/emacs"
[ -d "$dst/.git" ] && exit 0

# ~/.emacs.d wins over the XDG dir whenever it exists — a stray one would
# silently shadow the clone.
[ -e "$HOME/.emacs.d" ] && warn "stray ~/.emacs.d shadows ~/.config/emacs — remove it"

if [ -e "$dst" ]; then
  warn "$dst exists but is not a git clone — leaving it alone"
  exit 0
fi
command -v git >/dev/null 2>&1 \
  || { warn "git missing — rerun chezmoi apply after packages land"; exit 0; }
git clone https://github.com/saifulapm/emacs.d.git "$dst" \
  || { warn "clone failed (offline?) — rerun chezmoi apply"; exit 0; }
echo "emacs-config: cloned saifulapm/emacs.d -> ~/.config/emacs"
