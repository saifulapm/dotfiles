#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Toggle Night Light
# @vicinae.mode = silent
# @vicinae.icon = 🌙
# @vicinae.packageName = Toggles
# @vicinae.keywords = ["sunsetr"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec nightlight toggle
