#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Edit Screensaver Quotes
# @vicinae.mode = silent
# @vicinae.icon = 💬
# @vicinae.packageName = Setup
# @vicinae.keywords = ["nirisaver"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc '"${EDITOR:-vi}" "$HOME/.dotfiles/home/dot_config/nirisaver/quotes.txt"'
