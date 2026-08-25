#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Movies & TV
# @vicinae.mode = silent
# @vicinae.icon = 🍿
# @vicinae.packageName = Shell
# @vicinae.keywords = ["dekho", "media"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call dekho toggle
