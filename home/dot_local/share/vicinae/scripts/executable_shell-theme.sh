#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Switch Theme
# @vicinae.mode silent
# @vicinae.icon 🎭
# @vicinae.packageName Shell
# @vicinae.keywords ["theme", "switcher"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call theme toggle
