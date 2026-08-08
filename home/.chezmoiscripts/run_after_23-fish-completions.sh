#!/usr/bin/env bash
# fish completions for tools that can only SELF-generate — stripe today.
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

# stripe lives in ~/.local/bin (run_after_10), which bash sessions do NOT
# have on PATH — without this export the guard below never saw it on a fresh
# machine and the completions were silently never generated.
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

exit 0
