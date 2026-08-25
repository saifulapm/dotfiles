#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Theme Files
# @vicinae.mode silent
# @vicinae.icon 🗂️
# @vicinae.packageName Setup
# @vicinae.keywords ["toml"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float --working-directory="$HOME/.dotfiles/themes"
