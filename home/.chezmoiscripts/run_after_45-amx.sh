#!/usr/bin/env bash
# amx (github.com/saifulapm/amx) — coding agents as tmux panes: `amx new` cuts
# a worktree and starts claude in a pane, `amx ls` says which of them are
# working, waiting or done, and four exit codes say the same thing to a script.
# Ours outright, same shape as run_after_35-nirisaver and run_after_36-pxy:
# clone into ~/.local/src/amx, cargo-build, install to ~/.local/bin/amx.
# update-all's source-build sweep drops the binary when origin/main moved and
# this script rebuilds it on the apply behind it.
#
# It then runs `amx setup` for each agent this machine has, which is how the
# wiring arrives (2026-09-16). Three things used to be checked into this repo
# to do that job and none of them are any more:
#
#   * amx's seven hooks in home/dot_claude/modify_settings.json — amx no longer
#     writes anybody's settings file at all. claude reads them out of a plugin
#     directory now, ~/.claude/skills/amx, which it loads as amx@skills-dir.
#   * extraKnownMarketplaces + enabledPlugins, also in that file. The
#     marketplace was `source: "./"`, so claude cloned the whole amx repository
#     once per version installed — twelve gigabytes on this machine, one copy
#     having caught target/.
#   * home/dot_claude/skills/amx/SKILL.md and
#     home/dot_pi/agent/extensions/amx.ts, both verbatim copies of files the
#     binary already carries. Both were plain source files and therefore
#     chezmoi symlinks into this repo, and `amx setup` writes exactly those two
#     paths, so the two of them were shadow-wiring each other: apply restored
#     the symlink, setup replaced it, and whichever ran last won.
#
# `amx setup <agent>` is idempotent — an agent already carrying this amx's
# files is told "nothing to do" and nothing is written — so it runs on every
# apply rather than only on the install. That is the point: an amx upgrade
# changes the files it ships, and the checked-in copies went stale silently
# where this does not. `amx doctor` says which agent is unwired either way.
#
# Runtime deps are already declared elsewhere: tmux 3.2+ (the [[pkg]] entry —
# earlier tmux cannot address panes by id), git for the worktrees `new` cuts,
# and gh for the PR number on a row. Build needs only the rustup cargo from
# 03-dev-toolchain.
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

amx="$HOME/.local/bin/amx"

warn() { echo "amx: $*" >&2; }

# Wire whichever agents are installed. An agent this machine has not got is not
# something missing from it, which is the rule amx's own doctor follows.
wire() {
  [ -x "$amx" ] || return 0
  for agent in claude pi; do
    command -v "$agent" >/dev/null 2>&1 || continue
    "$amx" setup "$agent" >/dev/null || warn "setup $agent failed"
  done
}

if [ ! -x "$amx" ]; then
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
    install -m755 "$src/build/rust/release/amx" "$amx" \
      && echo "amx: installed to ~/.local/bin/amx" \
      || warn "install failed"
  else
    warn "build failed — try by hand: cd $src && CARGO_TARGET_DIR=build/rust cargo build --release"
  fi
fi

wire

exit 0
