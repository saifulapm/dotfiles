#!/usr/bin/env bash
# satty — the screenshot annotator behind Mod+Shift+A / Shift+Print and the
# capture menu's annotate rows. Fedora does not package it, but upstream
# ships release binaries for BOTH our arches, so unlike voxtype this install
# is scriptable: a guarded download into ~/.local/bin that no-ops once the
# binary exists. It links against GTK4, which the portal chain already put on
# this desktop; a machine where `satty --version` fails wants `dnf install
# gtk4`. Failure warns instead of aborting so a flaky network cannot stop the
# rest of a fresh-machine apply — the annotate rows just stay hidden.
set -uo pipefail

command -v satty >/dev/null 2>&1 && exit 0

VERSION="v0.22.0"
case "$(uname -m)" in
aarch64) asset="satty-aarch64-unknown-linux-gnu.tar.gz" ;;
x86_64) asset="satty-x86_64-unknown-linux-gnu.tar.gz" ;;
*)
  echo "satty: no upstream binary for $(uname -m)" >&2
  exit 0
  ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if curl -fsSL -o "$tmp/satty.tar.gz" "https://github.com/gabm/Satty/releases/download/$VERSION/$asset" &&
  tar -xzf "$tmp/satty.tar.gz" -C "$tmp" ./satty &&
  install -Dm755 "$tmp/satty" "$HOME/.local/bin/satty"; then
  echo "satty: installed $VERSION to ~/.local/bin"
else
  echo "satty: install failed — the annotate rows stay hidden until it exists" >&2
fi
exit 0
