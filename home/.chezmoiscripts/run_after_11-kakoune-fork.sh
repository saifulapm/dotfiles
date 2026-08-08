#!/usr/bin/env bash
# The editor's kakoune is the user's own fork (github.com/saifulapm/kakoune)
# with treesitter built in — NOT Fedora's kakoune package, which would fight
# it on PATH and lacks what the kak config's ts_* faces feed. Built once into
# ~/.local (bin/kak + share/kak); guarded, warn-don't-abort. Needs gcc-c++ and
# make from the manifest.
set -uo pipefail

warn() { echo "kakoune-fork: $*" >&2; }

[ -x "$HOME/.local/bin/kak" ] && exit 0

for dep in g++ make git; do
  command -v "$dep" >/dev/null 2>&1 || { warn "$dep missing — skipping (rerun after 00-install-packages lands)"; exit 0; }
done

src="$HOME/.local/src/kakoune"
# rev-parse, not [ -d .git ]: git creates .git early in a clone, so a clone
# killed mid-transfer satisfied the directory test forever and every later
# apply failed the build on a half-tree (audit 2026-08-08).
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/kakoune "$src" \
    || { warn "clone failed"; exit 0; }
fi

# The fork follows the newer upstream layout: Makefile at the repo root.
# CPPFLAGS: the vendored tree-sitter lexer includes "unicode/umachine.h",
# which only resolves with src/tree_sitter on the include path — the fork's
# Makefile compiles it with -Isrc alone and the build dies without this
# (found 2026-08-07; the vendored ICU-lite headers are right there in
# src/tree_sitter/unicode/).
echo "kakoune-fork: building (first run only)"
if make -C "$src" -j"$(nproc)" CPPFLAGS=-Isrc/tree_sitter >/dev/null 2>&1 \
  && make -C "$src" install PREFIX="$HOME/.local" >/dev/null 2>&1; then
  echo "kakoune-fork: installed to ~/.local/bin/kak"
else
  warn "build failed — try by hand: make -C ~/.local/src/kakoune CPPFLAGS=-Isrc/tree_sitter && make -C ~/.local/src/kakoune install PREFIX=~/.local"
fi

exit 0
