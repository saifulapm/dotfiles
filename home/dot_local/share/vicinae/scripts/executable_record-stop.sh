#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Stop Recording
# @vicinae.mode = silent
# @vicinae.icon = ⏹️
# @vicinae.packageName = Capture
# @vicinae.keywords = ["screenrecord"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenrecord stop
