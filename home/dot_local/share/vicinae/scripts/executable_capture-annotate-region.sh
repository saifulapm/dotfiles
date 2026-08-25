#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Screenshot Region (Annotate)
# @vicinae.mode silent
# @vicinae.icon ✏️
# @vicinae.packageName Capture
# @vicinae.keywords ["screenshot", "satty"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenshot-annotate --region
