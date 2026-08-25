#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Record Region (Desktop Audio)
# @vicinae.mode silent
# @vicinae.icon 🎬
# @vicinae.packageName Capture
# @vicinae.keywords ["screenrecord"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenrecord --region --with-desktop-audio
