#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Toggle Idle Locking
# @vicinae.mode silent
# @vicinae.icon 😴
# @vicinae.packageName Toggles
# @vicinae.keywords ["caffeine", "stay", "awake"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call idle toggle
