#!/usr/bin/env bash
# Omarchy's Qt Quick apps — omacalc (calculator), omawrite (writer), omacut
# (video trimmer) — built from source (MIT, github.com/omacom-io) with ONE
# patch: the two hardcoded omarchy theme-path literals in src/backend.cpp are
# pointed at ~/.local/state/qshell/oma-theme.toml, which templates/
# oma-theme.toml.tmpl emits from the active theme on every theme-apply. Their
# QFileSystemWatcher re-tints live, so the apps follow this desktop's theme
# switcher natively (user decision 2026-08-07, all three).
#
# Guarded per app; warn-don't-abort. Needs qmake6 (qt6-qtbase-devel) and the
# QML dev stack (qt6-qtdeclarative-devel) from the manifest. omacut also wants
# the ffmpeg CLI at runtime (ffmpeg-free).
set -uo pipefail

warn() { echo "oma-apps: $*" >&2; }

command -v qmake6 >/dev/null 2>&1 \
  || { warn "qmake6 missing (00-install-packages pending?) — skipping"; exit 0; }
command -v g++ >/dev/null 2>&1 \
  || { warn "g++ missing — skipping"; exit 0; }

bindir="$HOME/.local/bin"
appdir="$HOME/.local/share/applications"
mkdir -p "$bindir" "$appdir" "$HOME/.local/src"

build_app() {
  local app="$1" title="$2" categories="$3"
  [ -x "$bindir/$app" ] && return 0

  local src="$HOME/.local/src/$app"
  if [ ! -d "$src/.git" ]; then
    git clone --depth 1 "https://github.com/omacom-io/$app" "$src" \
      || { warn "$app: clone failed"; return 1; }
  fi

  # Re-point the omarchy theme paths at ours. Idempotent: after the first run
  # the omarchy literals are gone and sed matches nothing. The colors.toml
  # rename must come first — it is the longer, more specific literal.
  sed -i \
    -e 's|/.local/state/omarchy/current/theme/colors.toml|/.local/state/qshell/oma-theme.toml|g' \
    -e 's|/.local/state/omarchy/current|/.local/state/qshell|g' \
    -e 's|/colors.toml|/oma-theme.toml|g' \
    "$src/src/backend.cpp" 2>/dev/null || true

  echo "oma-apps: building $app (first run only)"
  local build="$src/build"
  mkdir -p "$build"
  if (cd "$build" && qmake6 .. >/dev/null && make -j"$(nproc)" >/dev/null 2>&1) \
      && [ -x "$build/$app" ]; then
    install -m755 "$build/$app" "$bindir/$app"
    cat >"$appdir/$app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$title
Exec=$HOME/.local/bin/$app
Categories=$categories
Terminal=false
EOF
    echo "oma-apps: installed $app"
  else
    warn "$app: build failed — try by hand in ~/.local/src/$app (qmake6 && make)"
    return 1
  fi
}

build_app omacalc "Calculator" "Utility;Calculator;" || true
build_app omawrite "Omawrite" "Office;WordProcessor;" || true
build_app omacut "Omacut" "AudioVideo;Video;" || true

exit 0
