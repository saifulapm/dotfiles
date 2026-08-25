#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Browse Wallpapers Online
# @vicinae.mode silent
# @vicinae.icon 🌌
# @vicinae.packageName Shell
# @vicinae.keywords ["wallhaven", "unsplash", "bing", "picsum", "wallpaper"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call wallhaven toggle
