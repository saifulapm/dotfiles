#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Record Region (Microphone)
# @vicinae.mode silent
# @vicinae.icon 🎬
# @vicinae.packageName Capture
# @vicinae.keywords ["screenrecord"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenrecord --region --with-microphone-audio
