#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Update Everything
# @vicinae.mode = silent
# @vicinae.icon = ⬆️
# @vicinae.packageName = System
# @vicinae.keywords = ["dnf", "upgrade"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc "just -f "$HOME/.dotfiles/justfile" update-all; read -r -p 'done — press enter to close'"
