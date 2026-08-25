#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Edit Shell Config
# @vicinae.mode silent
# @vicinae.icon ⚙️
# @vicinae.packageName Setup
# @vicinae.keywords ["shell.json"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc '"${EDITOR:-vi}" "$HOME/.dotfiles/shell/shell.json"'
