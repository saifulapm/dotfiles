#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Exit niri
# @vicinae.mode = silent
# @vicinae.icon = 🚪
# @vicinae.packageName = System
# @vicinae.keywords = ["logout", "quit"]
# @vicinae.needsConfirmation = true
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec niri msg action quit --skip-confirmation
