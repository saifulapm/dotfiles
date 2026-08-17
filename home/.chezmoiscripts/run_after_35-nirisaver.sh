#!/usr/bin/env bash
# nirisaver (github.com/saifulapm/nirisaver) — the screensaver: a native
# Wayland client that draws animated text on a wlr-layer-shell overlay, one
# surface per output, and rotates the quotes in
# ~/.config/nirisaver/quotes.txt (this repo owns that file; nothing here
# passes it a flag). Built once; guarded, warn-don't-abort, same shape as its
# sibling run_after_29-nirisnap.
#
# Needs only the rustup cargo from 03-dev-toolchain: no C toolchain, no Qt, no
# system wayland headers, no libxkbcommon-devel, not even a system font — the
# crate generates its own protocol bindings, dispatches wl_keyboard by hand
# rather than taking smithay-client-toolkit's xkbcommon default, and bundles
# the font it draws with. That last set is load-bearing rather than incidental:
# libxkbcommon-devel is on this machine only because gtk3-devel and
# qt6-qtbase-devel drag it in, so a build that started needing it would work
# here and fail on a machine without them. nirisaver's CI asserts the built
# binary links nothing but libc, libm and libgcc.
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "nirisaver: $*" >&2; }

[ -x "$HOME/.local/bin/nirisaver" ] && exit 0

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
  install -m755 "$src/build/rust/release/nirisaver" \
    "$HOME/.local/bin/nirisaver" \
    && echo "nirisaver: installed to ~/.local/bin/nirisaver" \
    || warn "install failed"
else
  warn "build failed — try by hand: cd $src && CARGO_TARGET_DIR=build/rust cargo build --release"
fi

exit 0
