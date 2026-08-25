#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Toggle Blur
# @vicinae.mode = silent
# @vicinae.icon = 🌫️
# @vicinae.packageName = Toggles
# @vicinae.keywords = ["frost", "glass"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call blur toggle
