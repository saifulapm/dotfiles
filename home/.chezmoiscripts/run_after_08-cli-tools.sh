#!/usr/bin/env bash
# Mac-parity tools that ride package managers already installed by earlier
# scripts: pnpm globals (language servers + npm-shipped formatters), deno via
# mise, php-cs-fixer via composer, mcp-language-server via go, and the four
# gh extensions the mac run.sh documents. All user-level, all guarded, all
# warn-don't-abort (same policy as 03-dev-toolchain: a flaky network must not
# stop the rest of an apply — rerun `chezmoi apply` to retry).
set -uo pipefail

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PNPM_HOME/bin:$HOME/.cargo/bin:$HOME/go/bin:$HOME/.local/bin:$PATH"

warn() { echo "cli-tools: $*" >&2; }

# ─── pnpm globals ────────────────────────────────────────────────────────────
# Binary name checked per package — @scoped names don't match their bin.
declare -A PNPM_PKGS=(
  [tsc]="typescript"
  [typescript-language-server]="typescript-language-server"
  [vtsls]="@vtsls/language-server"
  [intelephense]="intelephense"
  [astro-ls]="@astrojs/language-server"
  [biome]="@biomejs/biome"
  [dprint]="dprint"
  [rustywind]="rustywind"
  [ast-grep]="@ast-grep/cli"
  [prettier]="prettier"
  [vscode-eslint-language-server]="vscode-langservers-extracted"
  [emmet-language-server]="@olrtg/emmet-language-server"
)

if command -v mise >/dev/null 2>&1 && mise exec -- sh -c 'command -v pnpm' >/dev/null 2>&1; then
  mkdir -p "$PNPM_HOME"
  for bin in "${!PNPM_PKGS[@]}"; do
    if [ ! -e "$PNPM_HOME/bin/$bin" ] && [ ! -e "$PNPM_HOME/$bin" ]; then
      mise exec -- pnpm add -g "${PNPM_PKGS[$bin]}" >/dev/null 2>&1 \
        && echo "cli-tools: installed ${PNPM_PKGS[$bin]} (pnpm)" \
        || warn "pnpm add -g ${PNPM_PKGS[$bin]} failed"
    fi
  done
else
  warn "pnpm not available (mise/node missing?) — pnpm globals skipped"
fi

# ─── deno (mise, same mechanism as node; version declared in the ────────────
# ─── chezmoi-managed ~/.config/mise/config.toml) ─────────────────────────────
if command -v mise >/dev/null 2>&1 && ! mise which deno >/dev/null 2>&1; then
  mise install deno >/dev/null 2>&1 \
    && echo "cli-tools: deno installed via mise" \
    || warn "mise deno install failed"
fi

# ─── php-cs-fixer (composer global) ──────────────────────────────────────────
if command -v composer >/dev/null 2>&1 && ! command -v php-cs-fixer >/dev/null 2>&1; then
  if composer global require --quiet friendsofphp/php-cs-fixer >/dev/null 2>&1; then
    chome="$(composer global config home 2>/dev/null)"
    if [ -x "$chome/vendor/bin/php-cs-fixer" ]; then
      mkdir -p "$HOME/.local/bin"
      ln -sf "$chome/vendor/bin/php-cs-fixer" "$HOME/.local/bin/php-cs-fixer"
      echo "cli-tools: php-cs-fixer installed (composer)"
    fi
  else
    warn "composer global require php-cs-fixer failed"
  fi
fi

# ─── mcp-language-server (go, from the mac go.sh) ────────────────────────────
if command -v go >/dev/null 2>&1 && ! command -v mcp-language-server >/dev/null 2>&1; then
  if go install github.com/isaacphi/mcp-language-server@latest >/dev/null 2>&1; then
    gobin="$(go env GOBIN)"; [ -z "$gobin" ] && gobin="$(go env GOPATH)/bin"
    [ -x "$gobin/mcp-language-server" ] && {
      mkdir -p "$HOME/.local/bin"
      ln -sf "$gobin/mcp-language-server" "$HOME/.local/bin/mcp-language-server"
    }
    echo "cli-tools: mcp-language-server installed (go)"
  else
    warn "go install mcp-language-server failed"
  fi
fi

# ─── gh extensions ───────────────────────────────────────────────────────────
# gh extension install needs an authenticated gh; the login is interactive and
# deliberately not scripted (same policy as the agent CLIs). Until `gh auth
# login` has been run once, this skips loudly on every apply.
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    for ext in github/gh-stack fchimpan/gh-workflow-stats agynio/gh-pr-review dlvhdr/gh-dash; do
      gh extension list 2>/dev/null | grep -qF "$ext" && continue
      gh extension install "$ext" >/dev/null 2>&1 \
        && echo "cli-tools: installed $ext (gh)" \
        || warn "gh extension install $ext failed"
    done
  else
    warn "gh not authenticated — run 'gh auth login', then rerun 'chezmoi apply' for the gh extensions"
  fi
fi

exit 0
