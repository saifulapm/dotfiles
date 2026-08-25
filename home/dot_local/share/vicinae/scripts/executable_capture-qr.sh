#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Scan QR Code
# @vicinae.mode = silent
# @vicinae.icon = 🔳
# @vicinae.packageName = Capture
# @vicinae.keywords = ["qr"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenshot-qr
