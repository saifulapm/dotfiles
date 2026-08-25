#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Blur: Follow Theme
# @vicinae.mode = silent
# @vicinae.icon = 🌫️
# @vicinae.packageName = Toggles
# @vicinae.keywords = ["frost", "auto"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call blur auto
