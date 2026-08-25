#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Play a Track
# @vicinae.mode = silent
# @vicinae.icon = 🎵
# @vicinae.packageName = Music
# @vicinae.keywords = ["cliamp"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec music --prompt
