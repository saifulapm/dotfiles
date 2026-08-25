#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Annotate Last Capture
# @vicinae.mode = silent
# @vicinae.icon = 🖊️
# @vicinae.packageName = Capture
# @vicinae.keywords = ["screenshot"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenshot-annotate
