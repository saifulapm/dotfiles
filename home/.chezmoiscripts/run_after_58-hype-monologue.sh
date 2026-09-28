#!/usr/bin/env bash
# Omarchy's two newer Qt Quick apps (MIT, github.com/omacom — NOT omacom-io,
# where the oma apps live): Hype, Markdown presentations with a visual slide
# editor, and Monologue, a one-key webcam recorder (user decision 2026-09-28,
# omarchy gap report 2026-09-28). Same shape as run_after_13-oma-apps: clone
# into ~/.local/src, qmake6 + make, install to ~/.local; guarded on the
# installed binary, warn-don't-abort. `just update-all` rolls both forward
# through its source-build sweep, like the oma apps (they track main).
#
# Built and installed the way each repo's pkgbuild/PKGBUILD does it — its
# bin/build, then its own .desktop and .svg — verbatim, into ~/.local instead
# of /usr (the desktop files say `Exec=hype`/`Exec=monologue`, which resolves
# because ~/.local/bin is on the session PATH).
#
# UNPATCHED, unlike the oma apps: both read the omarchy theme from
# ~/.local/state/omarchy/current/theme/colors.toml and fall back to built-in
# colours without it. Pointing them at this desktop's theme is a separate,
# unapproved decision.
#
# Neither links Qt's private API (no *-private in QT +=), so a Fedora qt6
# patch bump does not break them the way it breaks quickshell. Deps, all in
# the manifest: qt6-qtbase-devel, qt6-qtdeclarative-devel,
# qt6-qtmultimedia-devel, libwebp-devel, zlib-ng-compat-devel (Hype links
# -lz -lwebpdemux -lwebp), pulseaudio-libs-devel (Monologue's libpulse); at
# runtime ffmpeg for both, and source-highlight, which Hype runs for code
# blocks.
set -uo pipefail

warn() { echo "hype-monologue: $*" >&2; }

for dep in qmake6 g++ make git; do
  command -v "$dep" >/dev/null 2>&1 \
    || { warn "$dep missing (00-install-packages pending?) — skipping"; exit 0; }
done

build_app() {
  local app="$1"
  [ -x "$HOME/.local/bin/$app" ] && return 0

  local src="$HOME/.local/src/$app"
  # rev-parse, not [ -d .git ] — a killed clone passes the directory test
  # forever (same guard as the oma apps and the kakoune fork).
  if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
    rm -rf "$src"
    mkdir -p "$HOME/.local/src"
    git clone --depth 1 "https://github.com/omacom/$app" "$src" \
      || { warn "$app: clone failed"; return 1; }
  fi

  echo "hype-monologue: building $app (first run only)"
  if "$src/bin/build" >/dev/null 2>&1 && [ -x "$src/build/$app" ]; then
    install -Dm755 "$src/build/$app" "$HOME/.local/bin/$app"
    install -Dm644 "$src/pkgbuild/$app.desktop" "$HOME/.local/share/applications/$app.desktop"
    install -Dm644 "$src/pkgbuild/$app.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/$app.svg"
    echo "hype-monologue: installed $app"
  else
    warn "$app: build failed — try by hand: ~/.local/src/$app/bin/build"
    return 1
  fi
}

build_app hype || true
build_app monologue || true

exit 0
