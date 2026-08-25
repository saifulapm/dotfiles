#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Choose Wallpaper
# @vicinae.mode silent
# @vicinae.icon 🖼️
# @vicinae.packageName Shell
# @vicinae.keywords ["background"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call wallpaper toggle
