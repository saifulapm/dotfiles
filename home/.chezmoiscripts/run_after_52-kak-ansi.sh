#!/usr/bin/env bash
# kak-ansi-filter — the helper binary behind kak/autoload/tools/ansi.kak, which
# colorizes ANSI escape codes in a buffer. That file is already in the config
# and hardcodes the path this script installs to:
#
#   declare-option -hidden str ansi_filter "~/.local/bin/kak-ansi-filter"
#
# Without the binary every `ansi-render` is a silent no-op, so colored output
# reaches the buffer as literal \e[0;32m. Two paths depend on it, and they are
# wired differently:
#
#   * piped-in buffers — ansi.kak's own `hook global BufCreate
#     '\*stdin(?:-\d+)?\*' ansi-enable`.
#   * fifo buffers — tools/fifo.kak calls `ansi-enable` itself, right after
#     `edit! -fifo`. These are named for their command (*aichat*, *grep*), NOT
#     *stdin*, so the hook above never sees them. This is the path that
#     matters most here: the aichat, make, grep, composer and php-artisan
#     wrappers all route through `fifo`.
#
# github.com/eraserhd/kak-ansi. ONE C file and a two-line Makefile — no cargo,
# no libraries, nothing to link against, so it is a source build rather than a
# prebuilt: upstream publishes no release binaries at all.
#
# The mac did this from .dotfiles/scripts/kak-ansi.sh, run by hand: clone to
# /tmp, make, cp the binary to ~/.local/bin, rm -rf the clone. Same repo, same
# build, same destination — the ONE change is that the checkout is KEPT, in
# ~/.local/src like every other source build here. A throwaway /tmp clone can
# never be rolled forward, so the mac's copy could only be updated by
# remembering to re-run the script; this one rides `just update-all`.
#
# Guarded on the binary, warn-don't-abort, same shape as run_after_11's
# kakoune fork. `just update-all` rolls it forward: the source-build sweep in
# bin/update-all fetches origin, and a moved HEAD deletes the binary so this
# script rebuilds it on the apply that follows.
set -uo pipefail

warn() { echo "kak-ansi: $*" >&2; }

[ -x "$HOME/.local/bin/kak-ansi-filter" ] && exit 0

for dep in cc make git; do
  command -v "$dep" >/dev/null 2>&1 || { warn "$dep missing — skipping (rerun after 00-install-packages lands)"; exit 0; }
done

src="$HOME/.local/src/kak-ansi"
# rev-parse rather than [ -d .git ], for the reason run_after_11 records: git
# creates .git early, so a clone killed mid-transfer would satisfy a directory
# test forever and every later apply would build a half-tree.
#
# No -b: upstream's default branch is `develop`, not master or main, and a
# plain clone follows whatever it moves to. update_src reads the branch back
# with rev-parse --abbrev-ref, so the sweep tracks the same one automatically.
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/eraserhd/kak-ansi "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "kak-ansi: building kak-ansi-filter"
if make -C "$src" >/dev/null 2>&1 && [ -x "$src/kak-ansi-filter" ]; then
  # Install via .part + mv so an interrupted copy cannot leave a truncated
  # binary that the -x guard above would then accept forever.
  install -m755 "$src/kak-ansi-filter" "$HOME/.local/bin/kak-ansi-filter.part" \
    && mv "$HOME/.local/bin/kak-ansi-filter.part" "$HOME/.local/bin/kak-ansi-filter" \
    && echo "kak-ansi: installed to ~/.local/bin/kak-ansi-filter"
  rm -f "$HOME/.local/bin/kak-ansi-filter.part"
else
  warn "build failed — try by hand: make -C ~/.local/src/kak-ansi"
fi

exit 0
