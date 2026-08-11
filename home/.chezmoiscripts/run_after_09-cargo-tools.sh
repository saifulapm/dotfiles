#!/usr/bin/env bash
# CLI tools Fedora does not package, built once with the rustup-managed cargo
# (03-dev-toolchain installs it). Guarded per binary, so only a fresh machine
# pays the compile time (the first run is long — nine crates); after that this
# is a no-op. Failures warn and continue: one crate's build break must not
# block the rest or the apply.
#
# kak-tree-sitter is deliberately NOT here — the kakoune fork (run_after_11)
# has treesitter built in. See the manifest's cargo-cli-tools entry.
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "cargo-tools: $*" >&2; }

if ! command -v cargo >/dev/null 2>&1; then
  warn "cargo missing (03-dev-toolchain skipped?) — nothing installed"
  exit 0
fi

# binary → crate
declare -A CRATES=(
  [sd]="sd"
  [sk]="skim"
  [tv]="television"
  [dufs]="dufs"
  [hop-kak]="hop-kak"
  [kak-popup]="kak-popup"
  [dedoc]="dedoc"
)
# ouch is NOT here: its cargo build needs libclang (libbzip3-sys bindgen) —
# it comes prebuilt from run_after_10-prebuilt-binaries.sh instead
# (verified 2026-08-07).

for bin in "${!CRATES[@]}"; do
  command -v "$bin" >/dev/null 2>&1 && continue
  echo "cargo-tools: building ${CRATES[$bin]} (first run only — this can take a while)"
  cargo install --quiet "${CRATES[$bin]}" \
    && echo "cargo-tools: installed ${CRATES[$bin]}" \
    || warn "cargo install ${CRATES[$bin]} failed"
done

# kakoune-lsp publishes NO crates.io release and its GitHub binaries cover
# x86_64-linux-musl + darwin only — no aarch64 linux (checked 2026-08-07).
# Git build is the one mechanism that works on every machine here.
if ! command -v kak-lsp >/dev/null 2>&1; then
  echo "cargo-tools: building kakoune-lsp from git (first run only)"
  cargo install --quiet --git https://github.com/kakoune-lsp/kakoune-lsp --locked \
    && echo "cargo-tools: installed kakoune-lsp" \
    || warn "cargo install kakoune-lsp (git) failed"
fi

# wayfreeze (user ask 2026-08-07): freezes the screen while slurp picks a
# region — screenshot-annotate/-ocr and screenrecord gate on its presence.
# No crates.io release, no packaged binary anywhere; git build only.
if ! command -v wayfreeze >/dev/null 2>&1; then
  echo "cargo-tools: building wayfreeze from git (first run only)"
  cargo install --quiet --git https://github.com/Jappie3/wayfreeze --locked \
    && echo "cargo-tools: installed wayfreeze" \
    || warn "cargo install wayfreeze (git) failed"
fi

# ttfx (user ask 2026-08-11, omarchy 4e31b61): Rust port of
# terminaltexteffects, the engine under bin/screensaver. The crates.io name
# is unclaimed (checked 2026-08-11), so install by git URL ONLY — a bare
# `cargo install ttfx` would hand the screensaver to whoever registers it.
if ! command -v ttfx >/dev/null 2>&1; then
  echo "cargo-tools: building ttfx from git (first run only)"
  cargo install --quiet --git https://github.com/omacom-io/ttfx --locked \
    && echo "cargo-tools: installed ttfx" \
    || warn "cargo install ttfx (git) failed"
fi

# herdr is NOT built here, though it can be: a git build understands seven
# config keys the release does not. It needs zig 0.15.2 EXACTLY (it vendors
# libghostty-vt, whose build.zig refuses every other version — Fedora's 0.16.0
# included), which means pinning an old zig through mise purely as a build
# dependency, plus 267 crates of compile on every fresh machine. Not worth it
# for seven cosmetic bindings: run_after_10 takes the release binary and
# home/dot_config/herdr/config.toml comments out what it cannot use.

exit 0
