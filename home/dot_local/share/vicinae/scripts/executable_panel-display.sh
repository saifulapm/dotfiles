#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Display Panel
# @vicinae.mode = silent
# @vicinae.icon = 🌙
# @vicinae.packageName = Panels
# @vicinae.keywords = ["night", "light", "brightness"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call bar open nightlight
