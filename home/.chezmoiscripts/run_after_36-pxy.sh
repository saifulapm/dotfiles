#!/usr/bin/env bash
# pxy (github.com/saifulapm/pxy) — the local LLM proxy: one endpoint on :4100
# over ~30 providers, free-first auto routing, `pxy launch claude|opencode|…`.
# Ours outright, same shape as run_after_35-nirisaver: clone into
# ~/.local/src/pxy, cargo-build, install to ~/.local/bin/pxy. update-all's
# source-build sweep drops the binary when origin/main moved and this script
# rebuilds it on the apply behind it.
#
# Config + unit arrive as chezmoi symlinks (dot_config/pxy, dot_config/
# systemd/user/pxy.service, ConditionPathExists-gated on the binary so a
# machine that never built it skips cleanly). Providers resolve credentials
# lazily per request via `pass show AI/...`, so the daemon starts fine before
# secrets-restore has run — requests just fail until the pass store arrives.
# Build needs only the rustup cargo from 03-dev-toolchain (rusqlite bundles
# its own sqlite; rustls, no openssl-devel).
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "pxy: $*" >&2; }

if [ -x "$HOME/.local/bin/pxy" ]; then
  exit 0
fi

command -v cargo >/dev/null 2>&1 || {
  warn "cargo missing (03-dev-toolchain skipped?) — skipping"
  exit 0
}

src="$HOME/.local/src/pxy"
# rev-parse, not [ -d .git ]: a clone killed mid-transfer must not satisfy
# the check forever (same guard as nirisaver and the kakoune fork).
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/pxy "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "pxy: building (first run only — this can take a while)"
# CARGO_TARGET_DIR inside the checkout so update-all's `rm -f` of the binary
# forces a reinstall while leaving the build dir for an incremental rebuild.
if (cd "$src" && CARGO_TARGET_DIR=build/rust cargo build --release --quiet); then
  mkdir -p "$HOME/.local/bin"
  install -m755 "$src/build/rust/release/pxy" "$HOME/.local/bin/pxy" \
    || { warn "install failed"; exit 0; }
  echo "pxy: installed to ~/.local/bin/pxy"
else
  warn "build failed — try by hand: cd $src && CARGO_TARGET_DIR=build/rust cargo build --release"
  exit 0
fi

# The unit was Condition-skipped while the binary was missing; now it can run.
# On a rebuild (update-all dropped the binary of a RUNNING daemon) this is a
# restart instead, so the new build actually serves.
systemctl --user daemon-reload
if systemctl --user is-active --quiet pxy; then
  systemctl --user restart pxy && echo "pxy: restarted on the new build"
else
  systemctl --user enable --now pxy 2>/dev/null \
    && echo "pxy: service enabled and started" \
    || warn "service not started (unit missing? chezmoi apply order)"
fi

exit 0
