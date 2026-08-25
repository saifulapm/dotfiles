#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Browse Wallhaven
# @vicinae.mode silent
# @vicinae.icon 🌌
# @vicinae.packageName Shell
# @vicinae.keywords ["wallpaper"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call wallhaven toggle
