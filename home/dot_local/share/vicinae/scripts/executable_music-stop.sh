#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Stop Music
# @vicinae.mode silent
# @vicinae.icon ⏹️
# @vicinae.packageName Music
# @vicinae.keywords ["cliamp"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec "$HOME/.local/bin/cliamp" stop
