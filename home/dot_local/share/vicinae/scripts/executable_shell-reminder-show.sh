#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Show Reminders
# @vicinae.mode = silent
# @vicinae.icon = ⏰
# @vicinae.packageName = Shell
# @vicinae.keywords = ["remind"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec reminder show
