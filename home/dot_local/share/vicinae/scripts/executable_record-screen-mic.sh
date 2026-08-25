#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Record Screen (Microphone)
# @vicinae.mode = silent
# @vicinae.icon = 🎥
# @vicinae.packageName = Capture
# @vicinae.keywords = ["screenrecord"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenrecord --fullscreen --with-microphone-audio
