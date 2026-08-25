#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Screenshot Window
# @vicinae.mode silent
# @vicinae.icon 🪟
# @vicinae.packageName Capture
# @vicinae.keywords ["screenshot"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec niri msg action screenshot-window
