#!/usr/bin/env bash
# nirisaver (github.com/saifulapm/nirisaver) — tobi's native Rust screensaver
# ported to niri, plus the quote rotation it reads out of
# ~/.config/nirisaver/quotes.txt on its own (this repo owns that file; nothing
# here passes it a flag). The binary keeps upstream's name, so this installs
# ~/.local/bin/omarchy-launch-screensaver. Built once; guarded,
# warn-don't-abort, same shape as its sibling run_after_29-nirisnap.
#
# Needs only the rustup cargo from 03-dev-toolchain: no C toolchain, no Qt,
# no system wayland headers — the crate generates its own protocol bindings.
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "nirisaver: $*" >&2; }

[ -x "$HOME/.local/bin/omarchy-launch-screensaver" ] && exit 0

command -v cargo >/dev/null 2>&1 || {
  warn "cargo missing (03-dev-toolchain skipped?) — skipping"
  exit 0
}

src="$HOME/.local/src/nirisaver"
# rev-parse, not [ -d .git ]: a clone killed mid-transfer must not satisfy
# the check forever (same guard as the kakoune fork and nirisnap).
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/nirisaver "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "nirisaver: building (first run only — this can take a while)"
# CARGO_TARGET_DIR inside the checkout so update-all's `rm -f` of the binary
# forces a reinstall while leaving the build dir for an incremental rebuild.
if (cd "$src" && CARGO_TARGET_DIR=build/rust cargo build --release --quiet); then
  mkdir -p "$HOME/.local/bin"
  install -m755 "$src/build/rust/release/omarchy-launch-screensaver" \
    "$HOME/.local/bin/omarchy-launch-screensaver" \
    && echo "nirisaver: installed to ~/.local/bin/omarchy-launch-screensaver" \
    || warn "install failed"
else
  warn "build failed — try by hand: cd $src && CARGO_TARGET_DIR=build/rust cargo build --release"
fi

exit 0
