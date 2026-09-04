#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Islamic Hub
# @vicinae.mode silent
# @vicinae.icon 🕌
# @vicinae.packageName Shell
# @vicinae.keywords ["quran", "recite", "deen", "কুরআন"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call deen toggle
