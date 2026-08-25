#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Transcode Video
# @vicinae.mode = silent
# @vicinae.icon = 🎞️
# @vicinae.packageName = Capture
# @vicinae.keywords = ["ffmpeg", "convert"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc 'transcode; read -r -p "press enter to close"'
