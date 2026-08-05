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

warn() { echo "dev-toolchain: $*" >&2; }

if command -v mise >/dev/null 2>&1; then
  # node, version-managed, global default in ~/.config/mise/config.toml
  if ! mise which node >/dev/null 2>&1; then
    mise use -g node@lts && echo "dev-toolchain: node installed via mise" \
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
    mise exec -- pnpm add -g @shopify/cli && echo "dev-toolchain: shopify CLI installed" \
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
  "$HOME/.cargo/bin/rustup" component add rust-analyzer >/dev/null 2>&1 \
    || warn "rust-analyzer component add failed"
fi

exit 0
