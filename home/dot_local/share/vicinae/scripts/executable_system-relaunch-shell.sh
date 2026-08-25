#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Relaunch Shell
# @vicinae.mode = silent
# @vicinae.icon = 🐚
# @vicinae.packageName = System
# @vicinae.keywords = ["qshell", "restart"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qshell-relaunch
