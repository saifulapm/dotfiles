#!/usr/bin/env bash
# Installs the dev toolchain the manifest's [[tool]] entries promise: node
# (mise), pnpm (corepack — never Bun), rust + rust-analyzer (rustup), and the
# Shopify CLI (pnpm). Everything is user-level (no root) and guarded, so
# re-runs are cheap no-ops. Runs BEFORE 99-bootstrap-theme by name order,
# which matters: bin/theme-apply runs node through `mise exec`.
#
# Failures warn instead of aborting: a flaky network must not stop the rest
# of a fresh-machine apply (the theme bootstrap degrades but the desktop
# still comes up; rerun `chezmoi apply` to retry).
set -uo pipefail

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PNPM_HOME/bin:$HOME/.cargo/bin:$PATH"

# Nothing below may ask a question: a fresh-machine apply is unattended (and
# when it is not, its prompts are invisible under the redirects). Two of them
# used to (fresh NUC 2026-08-10), and both are silenced here, not skipped:
#
#   1. corepack. pnpm IS a corepack shim, whose second line is
#      `COREPACK_ENABLE_DOWNLOAD_PROMPT ??= '1'`; before its first download it
#      then asks "? Do you want to continue? [Y/n]" and blocks on stdin
#      whenever stdin is a TTY. =0 skips the question, not the download.
#   2. pnpm's build-script approval. Since pnpm 10 a dependency with a
#      postinstall is ignored unless approved, interactively — @shopify/cli
#      brings esbuild, whose postinstall is what puts the real binary in
#      place, so skipping it is not an option either. --allow-build approves
#      that one package up front.
#
# stdin closed on top of both: an unattended apply must fail loudly, never
# hang. Nothing here reads it (sudo and the pi installer, which do prompt, use
# /dev/tty and live in other scripts).
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
exec </dev/null

warn() { echo "dev-toolchain: $*" >&2; }

if command -v mise >/dev/null 2>&1; then
  # node: version declared in the chezmoi-managed ~/.config/mise/config.toml
  # (node = "lts"); `mise install` reads that file without rewriting it
  if ! mise which node >/dev/null 2>&1; then
    mise install node && echo "dev-toolchain: node installed via mise" \
      || warn "node install failed (offline?) — theme bootstrap will degrade; rerun 'chezmoi apply'"
  fi
  # pnpm via corepack (shims land next to the mise-managed node)
  if mise which node >/dev/null 2>&1 && ! mise exec -- sh -c 'command -v pnpm' >/dev/null 2>&1; then
    mise exec -- sh -c 'corepack enable pnpm' && echo "dev-toolchain: pnpm enabled via corepack" \
      || warn "corepack enable pnpm failed"
  fi
  # Shopify CLI into PNPM_HOME/bin (already on PATH via dot_bashrc.d/10-dev.sh)
  if [ ! -x "$PNPM_HOME/bin/shopify" ] && mise exec -- sh -c 'command -v pnpm' >/dev/null 2>&1; then
    mkdir -p "$PNPM_HOME"
    mise exec -- pnpm add -g --allow-build=esbuild @shopify/cli && echo "dev-toolchain: shopify CLI installed" \
      || warn "shopify CLI install failed"
  fi
else
  warn "mise not on PATH — was 00-install-packages skipped? node/pnpm/shopify not installed"
fi

# rust: Fedora's rustup package ships /usr/bin/rustup-init, the real toolchain
# lands in ~/.cargo (dot_bash_profile sources ~/.cargo/env)
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  if command -v rustup-init >/dev/null 2>&1; then
    rustup-init -y --no-modify-path >/dev/null && echo "dev-toolchain: rust stable installed" \
      || warn "rustup-init failed"
  else
    warn "rustup-init missing — was 00-install-packages skipped?"
  fi
fi
if [ -x "$HOME/.cargo/bin/rustup" ]; then
  # rust-src alongside rust-analyzer: RA needs the stdlib sources for std
  # completion/navigation (eglot uses RA; without rust-src std items resolve
  # blind)
  "$HOME/.cargo/bin/rustup" component add rust-analyzer rust-src >/dev/null 2>&1 \
    || warn "rust-analyzer/rust-src component add failed"
fi

exit 0
