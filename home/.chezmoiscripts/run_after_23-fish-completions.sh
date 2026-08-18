#!/usr/bin/env bash
# fish completions for tools that can only SELF-generate — stripe and herdr.
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

# stripe and herdr live in ~/.local/bin (run_after_10), which bash sessions do
# NOT have on PATH — without this export the guards below never saw them on a
# fresh machine and the completions were silently never generated.
export PATH="$HOME/.local/bin:$PATH"

warn() { echo "fish-completions: $*" >&2; }
dest="$HOME/.config/fish/completions"
mkdir -p "$dest"

# validate_and_install <generated-file> <name>
#
# A completion file is CODE fish runs on every prompt, so a non-empty file is
# NOT good enough to install — it has to parse. cliamp taught this the hard
# way on 2026-08-18: its generator emitted a fully-formed, non-empty script
# whose every literal `%` had been mangled into a Go format error, and the
# `[ -s ]` check waved it through. The result was a syntax error printed in
# front of every command typed until the file was deleted by hand.
#
# `fish -n` is a parse-only check — it never sources or executes the file, so
# validating a hostile one is safe. On failure the OLD completion is left
# exactly where it is: a stale completion is a mild annoyance, a broken one
# breaks the shell.
validate_and_install() {
  local src="$1" name="$2"
  if [ ! -s "$src" ]; then
    warn "$name completion generation produced nothing — keeping the current one"
    return 1
  fi
  if ! fish -n "$src" 2>/dev/null; then
    warn "$name completion does not parse as fish — NOT installing it (generator bug upstream)"
    return 1
  fi
  install -m644 "$src" "$dest/$name.fish" || return 1
  echo "fish-completions: $name.fish regenerated"
}

# No fish, nothing to generate for.
command -v fish >/dev/null 2>&1 || exit 0

# stripe writes ./stripe.fish into the CWD (no output-path flag), so generate
# in a scratch dir — running it in a repo checkout litters the tree.
if command -v stripe >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  if (cd "$tmp" && stripe completion --shell fish >/dev/null 2>&1); then
    validate_and_install "$tmp/stripe.fish" stripe
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
  if herdr completion fish >"$tmp" 2>/dev/null; then
    validate_and_install "$tmp" herdr
  else
    warn "herdr completion generation failed"
  fi
  rm -f "$tmp"
fi

# cliamp is deliberately NOT here, though it has a `completion fish` verb.
# Its generator (urfave/cli's fish template) double-formats the script, so
# every literal `%` in the fish source comes back as a Go format error
# (`function __%!_(string=cliamp)perform_completion`, `printf
# "%!s(MISSING)\t%!s(MISSING)\n"`). Generated for exactly one apply on
# 2026-08-18, it put a syntax error in front of every prompt — fish sources
# this directory continuously. A hand-written, still-dynamic replacement lives
# in home/dot_config/fish/completions/cliamp.fish as a normal managed dotfile;
# its header says when to retry the generator.
#
# That incident is why the two above now go through validate_and_install
# instead of a bare `mv`: a completion file is CODE the shell runs on every
# prompt, and shipping generator output unread is how a broken upstream
# template becomes an unusable terminal.

exit 0
