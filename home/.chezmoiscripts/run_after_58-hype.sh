#!/usr/bin/env bash
# Omarchy's Hype (MIT, github.com/omacom — NOT omacom-io, where the oma apps
# live): Markdown presentations with a visual slide editor (user decision
# 2026-09-28, omarchy gap report 2026-09-28). Same shape as
# run_after_13-oma-apps: clone into ~/.local/src, qmake6 + make, install to
# ~/.local; guarded on the installed binary, warn-don't-abort. `just
# update-all` rolls it forward through its source-build sweep, like the oma
# apps (it tracks main).
#
# Built and installed the way the repo's pkgbuild/PKGBUILD does it — its
# bin/build, then its own .desktop and .svg — verbatim, into ~/.local instead
# of /usr (the desktop file says `Exec=hype`, which resolves because
# ~/.local/bin is on the session PATH).
#
# UNPATCHED, unlike the oma apps: it reads the omarchy theme from
# ~/.local/state/omarchy/current/theme/colors.toml and falls back to built-in
# colours without it. Pointing it at this desktop's theme is a separate,
# unapproved decision.
#
# It does not link Qt's private API (no *-private in QT +=), so a Fedora qt6
# patch bump does not break it the way it breaks quickshell. Deps, all in
# the manifest: qt6-qtbase-devel, qt6-qtdeclarative-devel,
# qt6-qtmultimedia-devel, libwebp-devel, zlib-ng-compat-devel (it links
# -lz -lwebpdemux -lwebp); at runtime ffmpeg, and source-highlight for code
# blocks.
#
# Monologue, omarchy's webcam recorder, was built here too until 2026-10-08
# (removed, user decision); the block at the end takes it off machines that
# still have it.
set -uo pipefail

warn() { echo "hype: $*" >&2; }

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

  echo "hype: building $app (first run only)"
  if "$src/bin/build" >/dev/null 2>&1 && [ -x "$src/build/$app" ]; then
    install -Dm755 "$src/build/$app" "$HOME/.local/bin/$app"
    install -Dm644 "$src/pkgbuild/$app.desktop" "$HOME/.local/share/applications/$app.desktop"
    install -Dm644 "$src/pkgbuild/$app.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/$app.svg"
    echo "hype: installed $app"
  else
    warn "$app: build failed — try by hand: ~/.local/src/$app/bin/build"
    return 1
  fi
}

build_app hype || true

# Monologue's install was `install`ed regular files, which run_after_50's
# dangling-link sweep never matches. Guarded on the desktop file being the
# one its pkgbuild wrote, like run_after_51; disarms once it is gone.
if grep -qs '^Exec=monologue' "$HOME/.local/share/applications/monologue.desktop"; then
  rm -rf "$HOME/.local/bin/monologue" \
    "$HOME/.local/share/applications/monologue.desktop" \
    "$HOME/.local/share/icons/hicolor/scalable/apps/monologue.svg" \
    "$HOME/.local/src/monologue" \
    && echo "hype: removed monologue (retired 2026-10-08)"
fi

exit 0
