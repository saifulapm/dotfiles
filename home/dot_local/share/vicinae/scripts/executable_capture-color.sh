#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Color Picker
# @vicinae.mode = silent
# @vicinae.icon = 🎨
# @vicinae.packageName = Capture
# @vicinae.keywords = ["pick", "hex"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec color-pick
