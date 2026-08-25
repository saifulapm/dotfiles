#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Notes
# @vicinae.mode silent
# @vicinae.icon 📝
# @vicinae.packageName Shell
# @vicinae.keywords ["capture"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call notes toggle
