#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Notification Center
# @vicinae.mode = silent
# @vicinae.icon = 🔔
# @vicinae.packageName = Panels
# @vicinae.keywords = ["notifications"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call notifs toggle
