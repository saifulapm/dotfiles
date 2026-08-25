#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Edit Niri Config
# @vicinae.mode = silent
# @vicinae.icon = ⚙️
# @vicinae.packageName = Setup
# @vicinae.keywords = ["compositor", "kdl"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc '"${EDITOR:-vi}" "$HOME/.dotfiles/home/dot_config/niri/config.kdl"'
