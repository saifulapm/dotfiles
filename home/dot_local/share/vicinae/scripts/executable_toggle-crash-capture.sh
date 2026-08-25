#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Toggle Crash Capture
# @vicinae.mode silent
# @vicinae.icon 💥
# @vicinae.packageName Toggles
# @vicinae.keywords ["coredump"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec crash-capture-toggle
