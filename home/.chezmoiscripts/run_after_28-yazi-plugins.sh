#!/usr/bin/env bash
# yazi plugins declared in ~/.config/yazi/package.toml, installed by yazi's own
# package manager (`ya pkg install`).
#
# Why this script exists: init.lua `require`s smart-enter, git and folder-rules
# at startup, and a missing plugin is not a degraded yazi — it is a hard
# "Error: Lua runtime failed" and no file manager at all. package.toml was in
# the repo from the start, but nothing ever installed from it, so the plugins
# existed only on the machine where they had once been added by hand. The
# fresh NUC (2026-08-10) had package.toml, no plugins, and a yazi that refused
# to start.
#
# Two kinds of plugin live side by side in ~/.config/yazi/plugins:
# the hand-written ones (arrow, smart-tab, folder-rules, …) are chezmoi
# symlinks into this repo, and the upstream ones below are real directories
# `ya` fetches. They never collide — different subdirectories — so this script
# only has to care about the second kind.
#
# `ya pkg install` re-fetches every dep whether or not it is present, so this
# runs only when one is actually missing: an apply with nothing to do costs no
# network. Warn-don't-abort, like the other user-tool scripts.
set -uo pipefail

warn() { echo "yazi-plugins: $*" >&2; }

package="$HOME/.config/yazi/package.toml"

[ -f "$package" ] || exit 0

if ! command -v ya >/dev/null 2>&1; then
  warn "ya not found (yazi not installed?) — skipping"
  exit 0
fi

# `use = "yazi-rs/plugins:smart-enter"` → smart-enter.yazi
# `use = "boydaihungst/restore"`        → restore.yazi
# The trailing segment after the last ':' or '/' is the plugin name; a `use`
# under [flavor] would be a flavour, not a plugin, so stop at that header.
missing=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -d "$HOME/.config/yazi/plugins/$name.yazi" ] || {
    missing=1
    echo "yazi-plugins: $name.yazi is missing"
  }
done < <(awk '
  /^[[:space:]]*\[flavor\]/ { exit }
  /^[[:space:]]*use[[:space:]]*=/ {
    v = $0
    sub(/^[^=]*=[[:space:]]*"/, "", v)
    sub(/".*$/, "", v)
    sub(/^.*[:\/]/, "", v)
    print v
  }
' "$package")

((missing)) || exit 0

if ya pkg install >/dev/null 2>&1; then
  echo "yazi-plugins: installed from package.toml"
else
  warn "ya pkg install failed (offline?) — rerun 'chezmoi apply'"
fi

exit 0
