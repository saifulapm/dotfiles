#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Restart Bluetooth
# @vicinae.mode = silent
# @vicinae.icon = 🟦
# @vicinae.packageName = System
# @vicinae.keywords = ["bt"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc 'bluetooth-restart; read -r -p "press enter to close"'
