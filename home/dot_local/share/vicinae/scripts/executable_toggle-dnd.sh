#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Toggle Do Not Disturb
# @vicinae.mode = silent
# @vicinae.icon = 🔕
# @vicinae.packageName = Toggles
# @vicinae.keywords = ["notifications"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call notifs toggleDnd
