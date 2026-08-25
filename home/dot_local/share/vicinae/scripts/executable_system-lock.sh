#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Lock Screen
# @vicinae.mode silent
# @vicinae.icon 🔒
# @vicinae.packageName System
# @vicinae.keywords ["lock"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call lock lock
