#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Switch Keyboard Layout
# @vicinae.mode silent
# @vicinae.icon 🔠
# @vicinae.packageName Toggles
# @vicinae.keywords ["language"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec niri msg action switch-layout next
