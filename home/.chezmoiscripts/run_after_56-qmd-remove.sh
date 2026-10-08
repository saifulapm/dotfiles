#!/usr/bin/env bash
# Sweeps up after qmd, the local document search behind vicinae's AI Chat,
# removed 2026-10-08 (user decision). run_after_56-qmd.sh built Saiful's fork
# (branch remote-models) into ~/.local/share/qmd/src and installed it as an
# npm global under the mise node; qmd-refresh.timer kept the index in
# ~/.cache/qmd. docs/qmd-2026-09-14.md is the write-up of what it was.
#
# The rest is cleaned elsewhere: run_after_02 stops and disables the timer,
# and run_after_50 sweeps the dangling links (the two units, qmd/index.yml).
# What neither can see is below — an npm global, a clone and a cache, none of
# them links into the repo.
#
# Every real node install, not just the active one: a `node = "lts"` bump
# leaves the old install with its globals, and the mise shim stays while any
# install still has a qmd. run_after_, not run_once_after_, for the reason
# run_after_39 spells out; the guards disarm it once everything is gone.
set -uo pipefail

for node in "$HOME"/.local/share/mise/installs/node/*/; do
  [ -L "${node%/}" ] && continue
  [ -d "$node/lib/node_modules/@tobilu/qmd" ] || continue
  if PATH="$node/bin:$PATH" npm uninstall -g --no-audit --no-fund @tobilu/qmd >/dev/null 2>&1; then
    echo "qmd-remove: uninstalled the npm global from $(basename "$node")"
    reshim=1
  else
    echo "qmd-remove: npm uninstall -g @tobilu/qmd failed under $(basename "$node")" >&2
  fi
done
[ -n "${reshim:-}" ] && command -v mise >/dev/null 2>&1 && mise reshim >/dev/null 2>&1

for dir in "$HOME/.local/share/qmd" "$HOME/.cache/qmd"; do
  [ -d "$dir" ] && rm -rf "$dir" && echo "qmd-remove: removed $dir"
done

exit 0
