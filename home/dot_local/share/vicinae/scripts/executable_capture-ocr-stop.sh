#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Stop Reading Aloud
# @vicinae.mode = silent
# @vicinae.icon = 🤫
# @vicinae.packageName = Capture
# @vicinae.keywords = ["speak", "tts"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenshot-ocr --stop
