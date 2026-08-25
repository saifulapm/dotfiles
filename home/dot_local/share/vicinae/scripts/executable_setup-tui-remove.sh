#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Remove TUI App
# @vicinae.mode silent
# @vicinae.icon 💻
# @vicinae.packageName Setup
# @vicinae.keywords ["terminal"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc "tui-remove; read -r -p 'press enter to close'"
