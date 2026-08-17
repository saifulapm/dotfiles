#!/usr/bin/env bash
# Creates the $HOME directories the configs assume exist. ~/Sites is the
# projects root: fish's `try` scaffolds experiments into ~/Sites/tries,
# `sweep` prunes node_modules/vendor under it, and mise auto-trusts project
# configs inside it (trusted_config_paths in ~/.config/mise/config.toml).
# A script rather than source-state because chezmoi cannot represent an
# empty directory without a .keep file — which symlink mode would render
# as a stray symlink into the repo.
set -euo pipefail

# Sites/laravel is the one subdirectory the *.test wildcard serves — caddy
# resolves app.test to Sites/laravel/app/public, so the directory has to exist
# before a project can be dropped into it (see caddy/Caddyfile.tmpl).
mkdir -p "$HOME/Sites/laravel"

# GOBIN (~/.config/go/env homes go there) — pre-created because fish_add_path
# silently skips directories that don't exist yet, leaving GOBIN off PATH
# until a login after the first `go install`.
mkdir -p "$HOME/.local/share/go/bin"

exit 0
