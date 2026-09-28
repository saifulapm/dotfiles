#!/usr/bin/env bash
# elfeed-kak — the feed reader behind kak/autoload/tools/feed.kak, replacing
# Emacs elfeed. github.com/saifulapm/kakfeed: one Rust binary over SQLite;
# `elfeed-kak init` prints the Kakoune glue, so there is no rc file to install.
# Subscriptions live in ~/.config/elfeed-kak/config.toml (chezmoi-managed).
#
# Same shape as run_after_52-kak-ansi: guarded on the binary, source kept in
# ~/.local/src so the `just update-all` sweep can roll it forward (a moved
# HEAD deletes the binary and the next apply rebuilds), warn-don't-abort.
set -uo pipefail

warn() { echo "elfeed-kak: $*" >&2; }

[ -x "$HOME/.local/bin/elfeed-kak" ] && exit 0

for dep in cargo git; do
  command -v "$dep" >/dev/null 2>&1 || { warn "$dep missing — skipping (rerun after 00-install-packages lands)"; exit 0; }
done

src="$HOME/.local/src/kakfeed"
# rev-parse, not [ -d .git ] — see run_after_52 for why.
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/kakfeed "$src" \
    || { warn "clone failed"; exit 0; }
fi

echo "elfeed-kak: building (cargo, release)"
if (cd "$src" && cargo build --release --quiet) && [ -x "$src/target/release/elfeed-kak" ]; then
  install -m755 "$src/target/release/elfeed-kak" "$HOME/.local/bin/elfeed-kak.part" \
    && mv "$HOME/.local/bin/elfeed-kak.part" "$HOME/.local/bin/elfeed-kak" \
    && echo "elfeed-kak: installed to ~/.local/bin/elfeed-kak"
  rm -f "$HOME/.local/bin/elfeed-kak.part"
else
  warn "build failed — try by hand: cd ~/.local/src/kakfeed && cargo build --release"
fi

exit 0
