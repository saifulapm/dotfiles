#!/usr/bin/env bash
# Theme wallpapers — omarchy's per-theme backgrounds, ~105 MB, previously the
# `.local/share/qshell/backgrounds` entry in .chezmoiexternal.toml. Moved
# here (audit 2026-08-08) because externals are fetched while chezmoi reads
# the SOURCE STATE: one GitHub timeout or 5xx on this tarball aborted
# `init --apply` before a single package installed or file landed — verified
# in a sandbox, where the whole run died with one bare Go HTTP error and the
# destination stayed empty. The biggest download in the repo was the whole
# apply's single point of failure. As a script, the same failure warns, the
# desktop merely lacks wallpapers, and the next apply retries.
#
# Pin and layout are unchanged from the external it replaces: same commit as
# the ~/ref/omarchy research checkout on 2026-08-07 (colors credited in
# CREDITS.md), and the strip-components=2 extraction lands files as
# <theme>/backgrounds/<image> — the layout bin/background-next and
# bin/theme-list read. User wallpapers go in ~/Pictures/Wallpapers instead;
# this directory belongs to this script now. Runs before 99-bootstrap-theme
# by lexical order, so the first theme activation has images to point at.
set -uo pipefail

SHA=fd1034f71b16aa45d5431ab41ed9e48c89fdac8e
SUM=bf7491e56090813e180a569a1a53cd491472868e10adbb077ca40edfb1d34e9f
dest="$HOME/.local/share/qshell/backgrounds"
stamp="$dest/.pin"

warn() { echo "wallpapers: $*" >&2; }

[ "$(cat "$stamp" 2>/dev/null)" = "$SHA" ] && exit 0

# Machines that predate this script got these exact bytes from the external
# (same pin — the external was never bumped). Adopt instead of re-downloading
# 105 MB three times.
if [ ! -f "$stamp" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
  echo "$SHA" >"$stamp"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if curl -fsSL -o "$tmp/omarchy.tar.gz" \
  "https://github.com/basecamp/omarchy/archive/$SHA.tar.gz" &&
  echo "$SUM  $tmp/omarchy.tar.gz" | sha256sum -c --quiet - &&
  mkdir -p "$tmp/x" &&
  tar -xzf "$tmp/omarchy.tar.gz" -C "$tmp/x" \
    --strip-components=2 --wildcards '*/themes/*/backgrounds/*'; then
  mkdir -p "$dest"
  # Overlay copy, then stamp last — an interrupted copy leaves the stamp
  # unwritten, so the next apply redoes it. (A pin bump overlays rather than
  # prunes; themes removed upstream would need a one-off manual clean.)
  cp -a "$tmp/x/." "$dest/" &&
    echo "$SHA" >"$stamp" &&
    echo "wallpapers: fetched omarchy backgrounds ($SHA)"
else
  warn "fetch failed — theme backgrounds missing until the next 'chezmoi apply'"
fi
exit 0
