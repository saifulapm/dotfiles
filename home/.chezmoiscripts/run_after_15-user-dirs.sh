#!/usr/bin/env bash
# Creates the $HOME directories the configs assume exist. ~/Sites is the
# projects root: fish's `try` scaffolds experiments into ~/Sites/tries,
# `sweep` prunes node_modules/vendor under it, and mise auto-trusts project
# configs inside it (trusted_config_paths in ~/.config/mise/config.toml).
# A script rather than source-state because chezmoi cannot represent an
# empty directory without a .keep file — which symlink mode would render
# as a stray symlink into the repo.
set -euo pipefail

mkdir -p "$HOME/Sites"

exit 0
