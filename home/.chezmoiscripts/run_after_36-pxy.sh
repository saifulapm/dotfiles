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

src="$HOME/.local/src/pxy"

# ------------------------------------------------------------ pi extension
# `pxy launch pi` writes ~/.pi/agent/extensions/pxy.ts, and it is the ONLY
# thing that writes it — so a pi started by hand gets no pxy provider at all,
# while home/dot_pi/agent/modify_settings.json names "pxy" as defaultProvider
# on every machine. This does what launch does, minus the launch: the
# extension ships in the pxy repo as contrib/pi-pxy.ts with two placeholders,
# and src/launch.rs install_pi_extension fills them with `{base_url}/v1` and
# the path of the running pxy. Both are known here — the port from the
# config.toml this repo already owns, the path from where we install.
#
# GENERATED rather than checked into this repo on purpose: it is written from
# the same checkout the binary was built from, so the extension can never be a
# version out of step with the pxy it calls. amx's is written by `amx setup
# pi`, which run_after_45-amx.sh runs on every apply — it was checked in until
# 2026-09-16, and being both checked in and written is how a copy goes a
# version stale without saying so. mem's is written by `mem doctor --fix`,
# which run_after_46-workflow.sh runs on every apply. Three extensions, three
# owners, none of them two.
#
# Watch out for ~/.pi/agent/models.json: a providers.pxy key left there by the
# pre-extension merge shadows this file silently (launch.rs says so outright),
# because models.json overrides compose ABOVE registered providers.
write_pi_extension() {
  tpl="$src/contrib/pi-pxy.ts"
  out="$HOME/.pi/agent/extensions/pxy.ts"
  cfg="$HOME/.config/pxy/config.toml"

  [ -r "$tpl" ] || {
    warn "contrib/pi-pxy.ts missing (checkout older than the extension) — pi extension not written"
    return
  }

  port=$(sed -n 's/^port *= *\([0-9]\{1,\}\).*/\1/p' "$cfg" 2>/dev/null | head -1)
  [ -n "$port" ] || {
    warn "no [server] port in $cfg — pi extension not written"
    return
  }

  mkdir -p "$(dirname "$out")"
  tmp=$(mktemp "$out.XXXXXX") || return
  sed -e "s|__PXY_BASE_URL__|http://127.0.0.1:$port/v1|" \
      -e "s|__PXY_BIN__|$HOME/.local/bin/pxy|" "$tpl" >"$tmp"

  # A placeholder pxy grew since this was written would otherwise ship as a
  # literal __PXY_*__ inside live TypeScript.
  if grep -q '__PXY_[A-Z_]*__' "$tmp"; then
    rm -f "$tmp"
    warn "unsubstituted placeholder in pi-pxy.ts — pi extension not written; run \`pxy launch pi\` once and teach this script the new one"
    return
  fi

  # Quiet when nothing changed, like workflow's and mem's doctors.
  if cmp -s "$tmp" "$out"; then
    rm -f "$tmp"
    return
  fi
  chmod 644 "$tmp"
  mv "$tmp" "$out" && echo "pxy: wrote the pi extension to $out"
}

if [ -x "$HOME/.local/bin/pxy" ]; then
  write_pi_extension
  exit 0
fi

command -v cargo >/dev/null 2>&1 || {
  warn "cargo missing (03-dev-toolchain skipped?) — skipping"
  exit 0
}

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
  # After the install, not before: the extension names the binary it calls.
  write_pi_extension
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
