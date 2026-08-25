#!/usr/bin/env bash
# amx (github.com/saifulapm/amx) — coding agents as tmux panes: `amx new` cuts
# a worktree and starts claude in a pane, `amx ls` says which of them are
# working, waiting or done, and four exit codes say the same thing to a script.
# Ours outright, same shape as run_after_35-nirisaver and run_after_36-pxy:
# clone into ~/.local/src/amx, cargo-build, install to ~/.local/bin/amx.
# update-all's source-build sweep drops the binary when origin/main moved and
# this script rebuilds it on the apply behind it.
#
# Nothing here runs `amx doctor --fix`, which is the one thing the README tells
# a person to run after installing. It wires amx's seven hooks into
# ~/.claude/settings.json — and that file is a chezmoi symlink into this repo,
# so a --fix would write the hooks THROUGH the symlink into the source tree and
# leave the repo dirty on every machine that applied. The hooks are checked in
# instead (home/dot_claude/settings.json, seven entries pointing at
# ~/.local/bin/amx) and arrive with the rest of the config. `amx doctor` still
# reports honestly; it just has nothing left to repair.
#
# Runtime deps are already declared elsewhere: tmux 3.2+ (the [[pkg]] entry —
# earlier tmux cannot address panes by id), git for the worktrees `new` cuts,
# and gh for the PR number on a row. Build needs only the rustup cargo from
# 03-dev-toolchain.
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "amx: $*" >&2; }

[ -x "$HOME/.local/bin/amx" ] && exit 0

command -v cargo >/dev/null 2>&1 || {
  warn "cargo missing (03-dev-toolchain skipped?) — skipping"
  exit 0
}

src="$HOME/.local/src/amx"
# rev-parse, not [ -d .git ]: a clone killed mid-transfer must not satisfy
# the check forever (same guard as nirisaver, pxy and the kakoune fork).
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/amx "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "amx: building (first run only — this can take a while)"
# CARGO_TARGET_DIR inside the checkout so update-all's `rm -f` of the binary
# forces a reinstall while leaving the build dir for an incremental rebuild.
if (cd "$src" && CARGO_TARGET_DIR=build/rust cargo build --release --quiet); then
  mkdir -p "$HOME/.local/bin"
  install -m755 "$src/build/rust/release/amx" "$HOME/.local/bin/amx" \
    && echo "amx: installed to ~/.local/bin/amx" \
    || warn "install failed"
else
  warn "build failed — try by hand: cd $src && CARGO_TARGET_DIR=build/rust cargo build --release"
fi

exit 0
