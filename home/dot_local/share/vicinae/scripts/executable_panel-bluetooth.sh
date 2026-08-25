#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Bluetooth Panel
# @vicinae.mode silent
# @vicinae.icon 🟦
# @vicinae.packageName Panels
# @vicinae.keywords ["bt"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call bluetooth toggle
