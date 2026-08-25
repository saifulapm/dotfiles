#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = AI Usage
# @vicinae.mode = silent
# @vicinae.icon = 🤖
# @vicinae.packageName = Panels
# @vicinae.keywords = ["claude", "codex"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call bar open ai
