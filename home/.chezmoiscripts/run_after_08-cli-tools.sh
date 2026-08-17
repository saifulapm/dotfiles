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

# pnpm here is a COREPACK SHIM (node/…/bin/pnpm → corepack/dist/pnpm.js), and
# that shim's second line is `COREPACK_ENABLE_DOWNLOAD_PROMPT ??= '1'`. Before
# its first download corepack then asks "? Do you want to continue? [Y/n]" on
# stderr and blocks reading stdin — whenever stdin is a TTY and CI is unset,
# which is exactly a console `chezmoi apply`. Every pnpm call below sends
# stderr to /dev/null, so on the fresh NUC (2026-08-10) that question was
# INVISIBLE: the apply simply stopped dead after satty's line until a key was
# pressed. Opting out of the prompt is the documented fix; it does not skip the
# download, only the question.
#
# stdin closed for the same reason 03-dev-toolchain closes it: pnpm's
# build-script approval prompt (and anything like it a future package manager
# grows) can only hang an apply that hands it a TTY. Nothing here reads stdin.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
exec </dev/null

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
  [tailwindcss-language-server]="@tailwindcss/language-server"
  # Not a language server — the agent-side browser CLI from the mac (config in
  # home/dot_agent-browser). A plain Node package: its npm metadata declares no
  # os/cpu restriction, so aarch64 Linux is fine.
  [agent-browser]="agent-browser"
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

# @ast-grep/cli ships TWO bins: `ast-grep` and the short alias `sg`. The short
# one SHADOWS /usr/bin/sg (shadow-utils' "run a command under a different
# group") because PNPM_HOME/bin is ahead of /usr/bin on PATH — so `sg input -c
# …` silently runs ast-grep, which fails with "unrecognized subcommand 'input'"
# and sends you hunting the wrong bug. Hit 2026-08-11 starting ydotoold without
# a re-login (see run_after_31-ydotool.sh, which documents exactly that
# invocation). ast-grep itself prints "`sg` is deprecated, use `ast-grep`", so
# dropping the alias costs nothing; `ast-grep` in the same directory is
# untouched.
#
# Outside the install loop above, and unguarded by any "did we just install it"
# check, because pnpm recreates the shim on every install or update of the
# package — this has to run on every apply to stay removed.
if [ -e "$PNPM_HOME/bin/sg" ]; then
  rm -f "$PNPM_HOME/bin/sg" \
    && echo "cli-tools: removed pnpm's sg shim (it shadowed /usr/bin/sg; use ast-grep)" \
    || warn "could not remove $PNPM_HOME/bin/sg"
fi

# ─── deno (mise, same mechanism as node; version declared in the ────────────
# ─── chezmoi-managed ~/.config/mise/config.toml) ─────────────────────────────
if command -v mise >/dev/null 2>&1 && ! mise which deno >/dev/null 2>&1; then
  mise install deno >/dev/null 2>&1 \
    && echo "cli-tools: deno installed via mise" \
    || warn "mise deno install failed"
fi

# ─── laravel installer (composer global — `laravel new`, Herd parity) ────────
if command -v composer >/dev/null 2>&1 && [ ! -e "$HOME/.config/composer/vendor/bin/laravel" ]; then
  composer global require --quiet laravel/installer >/dev/null 2>&1 \
    && echo "cli-tools: laravel installer installed (composer global)" \
    || warn "composer global require laravel/installer failed"
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

# ─── goimapnotify (go) — IMAP IDLE for the mail setup ────────────────────────
# The push half of the HEY mail workflow: holds an IDLE connection per mailbox
# and runs bin/mail-sync within about a second of the server announcing new
# mail. Without it the setup still works — mail-sync.timer polls every 15
# minutes — so a failure here degrades rather than breaks, which is why it
# only warns.
#
# The /cmd/goimapnotify suffix is load-bearing: the module ROOT contains no
# main package, and `go install gitlab.com/shackra/goimapnotify@latest` fails
# with "does not contain package". Upstream publishes no tags, so @latest
# resolves to a pseudo-version and a rebuild is the only way to move.
#
# Sits here beside mcp-language-server rather than in a mail-specific script:
# it is one more go binary, and packages/manifest.toml points at this file.
if command -v go >/dev/null 2>&1 && ! command -v goimapnotify >/dev/null 2>&1; then
  if go install gitlab.com/shackra/goimapnotify/cmd/goimapnotify@latest >/dev/null 2>&1; then
    gobin="$(go env GOBIN)"; [ -z "$gobin" ] && gobin="$(go env GOPATH)/bin"
    [ -x "$gobin/goimapnotify" ] && {
      mkdir -p "$HOME/.local/bin"
      ln -sf "$gobin/goimapnotify" "$HOME/.local/bin/goimapnotify"
    }
    echo "cli-tools: goimapnotify installed (go)"
  else
    warn "go install goimapnotify failed — mail falls back to mail-sync.timer (15 min)"
  fi
fi

# ─── gh extensions ───────────────────────────────────────────────────────────
# gh extension install needs an authenticated gh; the login is interactive and
# deliberately not scripted (same policy as the agent CLIs). Until `gh auth
# login` has been run once, this skips loudly on every apply.
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    # `grep -F >/dev/null`, never `grep -qF`: -q exits at the first match, which
    # SIGPIPEs `gh extension list` mid-write, so pipefail reported 141 for an
    # already-installed extension. Every apply then reinstalled all four and
    # printed a false "installed" line (gh exits 0 on "already installed").
    for ext in github/gh-stack fchimpan/gh-workflow-stats agynio/gh-pr-review dlvhdr/gh-dash; do
      gh extension list 2>/dev/null | grep -F "$ext" >/dev/null && continue
      gh extension install "$ext" >/dev/null 2>&1 \
        && echo "cli-tools: installed $ext (gh)" \
        || warn "gh extension install $ext failed"
    done
  else
    warn "gh not authenticated — run 'gh auth login', then rerun 'chezmoi apply' for the gh extensions"
  fi
fi

exit 0
