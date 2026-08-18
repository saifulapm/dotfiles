#!/usr/bin/env bash
# fish completions for tools that can only SELF-generate — stripe, herdr and
# cliamp.
# Regenerated into ~/.config/fish/completions on every apply (that dir also
# holds the chezmoi-symlinked static completions; chezmoi never deletes
# unmanaged files, so the two coexist).
#
# Deliberately NOT here (surveyed 2026-08-08): chezmoi/just/mise/gh/podman &
# co ship rpm vendor completions; fish itself ships composer/cargo/go/node/
# npm/pnpm/git; artisan + the repo's own commands are static files in
# dot_config/fish/completions; shopify-cli and claude expose no completion
# machinery at all; hurl/usql/cloudflared/watchexec/dufs ship none outside
# release tarballs we don't unpack. Composer's own `completion` command is
# bash-only in the Fedora build — fish's shipped file covers it.
set -uo pipefail

# stripe, herdr and cliamp live in ~/.local/bin (run_after_10), which bash
# sessions do NOT have on PATH — without this export the guards below never saw
# them on a fresh machine and the completions were silently never generated.
export PATH="$HOME/.local/bin:$PATH"

warn() { echo "fish-completions: $*" >&2; }
dest="$HOME/.config/fish/completions"
mkdir -p "$dest"

# stripe writes ./stripe.fish into the CWD (no output-path flag), so generate
# in a scratch dir — running it in a repo checkout litters the tree.
if command -v stripe >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  if (cd "$tmp" && stripe completion --shell fish >/dev/null 2>&1) && [ -s "$tmp/stripe.fish" ]; then
    mv -f "$tmp/stripe.fish" "$dest/stripe.fish"
    echo "fish-completions: stripe.fish regenerated"
  else
    warn "stripe completion generation failed"
  fi
  rm -rf "$tmp"
fi

# herdr writes to stdout, so no scratch dir — but do NOT redirect straight
# into the destination: a failed run would leave a truncated file that fish
# then sources on every prompt.
if command -v herdr >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if herdr completion fish >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dest/herdr.fish"
    chmod 644 "$dest/herdr.fish"
    echo "fish-completions: herdr.fish regenerated"
  else
    rm -f "$tmp"; warn "herdr completion generation failed"
  fi
fi

# cliamp — same stdout shape as herdr, same reason for the scratch file. Worth
# having: the completion covers the whole `playlist`/`history`/`device` verb
# tree and the provider and EQ-preset names, which is most of what the CLI is.
if command -v cliamp >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if cliamp completion fish >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dest/cliamp.fish"
    chmod 644 "$dest/cliamp.fish"
    echo "fish-completions: cliamp.fish regenerated"
  else
    rm -f "$tmp"; warn "cliamp completion generation failed"
  fi
fi

exit 0
