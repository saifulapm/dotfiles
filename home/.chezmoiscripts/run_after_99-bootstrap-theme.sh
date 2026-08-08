#!/bin/bash
# First-boot theme bootstrap: if no active theme exists yet, activate the
# default so the foot and GTK configs are generated and the shell has tokens.
#
# $CHEZMOI_WORKING_TREE, never `chezmoi source-path`: the outer apply holds an
# exclusive lock on the persistent-state DB across run_after scripts, so a
# nested chezmoi call times out on the lock, the substitution came back empty,
# and set -e killed the apply with exit 127 on every fresh machine (audit
# 2026-08-07 — invisible on the dev MacBook, whose theme.toml predates it).
#
# Warn-don't-abort like every other run_after: theme-set ends in theme-apply,
# whose node comes from 03-dev-toolchain — a script that deliberately
# tolerates an offline install failure. The desktop must still come up; the
# next `chezmoi apply` retries.
set -uo pipefail
state="$HOME/.local/state/qshell/theme.toml"
# Gate on theme-apply's OUTPUT, not just theme.toml (audit 2026-08-08):
# theme-set writes theme.toml BEFORE exec-ing theme-apply, so a failed first
# apply (node missing — 03 tolerates an offline mise install) used to satisfy
# the old theme.toml-only gate and leave the desktop permanently unthemed,
# with every rerun skipping here. niri-theme.kdl is the apply half's first
# artifact; while it is missing, re-run the apply half directly — theme-set
# would work too, but it would also reset a user-chosen theme back to the
# default, and theme.toml existing means the choice already happened.
applied="$HOME/.local/state/qshell/niri-theme.kdl"
if [ ! -f "$state" ]; then
  if ! "${CHEZMOI_WORKING_TREE:?}/bin/theme-set" tokyo-night; then
    echo "bootstrap-theme: theme-set failed (node missing? offline?) — rerun 'chezmoi apply'" >&2
  fi
elif [ ! -f "$applied" ]; then
  if ! "${CHEZMOI_WORKING_TREE:?}/bin/theme-apply"; then
    echo "bootstrap-theme: theme-apply failed (node missing? offline?) — rerun 'chezmoi apply'" >&2
  fi
fi
exit 0
