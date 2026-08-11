#!/usr/bin/env bash
# nirisnap (github.com/saifulapm/nirisnap) — tobi's omasnap ported to niri:
# region/fullscreen screenshot + annotation overlay, bound at Print and
# Mod+Shift+4 in the niri config. The binary keeps upstream's name, so this
# installs ~/.local/bin/omasnap. Built once; guarded, warn-don't-abort. Needs
# cmake, gcc-c++, qt6-qtbase-devel, layer-shell-qt-devel, wayland-devel and
# wayland-protocols-devel from the manifest.
set -uo pipefail

warn() { echo "nirisnap: $*" >&2; }

[ -x "$HOME/.local/bin/omasnap" ] && exit 0

for dep in cmake g++ git wayland-scanner; do
  command -v "$dep" >/dev/null 2>&1 || { warn "$dep missing — skipping (rerun after 00-install-packages lands)"; exit 0; }
done

src="$HOME/.local/src/nirisnap"
# rev-parse, not [ -d .git ]: same half-clone guard as the kakoune fork —
# a clone killed mid-transfer must not satisfy the check forever.
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/nirisnap "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "nirisnap: building (first run only)"
if cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_INSTALL_PREFIX="$HOME/.local" >/dev/null 2>&1 \
  && cmake --build "$src/build" --parallel >/dev/null 2>&1 \
  && cmake --install "$src/build" >/dev/null 2>&1; then
  echo "nirisnap: installed to ~/.local/bin/omasnap"
else
  warn "build failed — try by hand: cmake -S ~/.local/src/nirisnap -B ~/.local/src/nirisnap/build -DCMAKE_INSTALL_PREFIX=~/.local && cmake --build ~/.local/src/nirisnap/build --parallel && cmake --install ~/.local/src/nirisnap/build"
fi

exit 0
