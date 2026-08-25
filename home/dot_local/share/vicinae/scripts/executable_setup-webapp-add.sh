#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Add Web App
# @vicinae.mode = silent
# @vicinae.icon = 🌐
# @vicinae.packageName = Setup
# @vicinae.keywords = ["chromium"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc "webapp-install; read -r -p 'press enter to close'"
