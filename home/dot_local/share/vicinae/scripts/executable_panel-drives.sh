#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Removable Drives
# @vicinae.mode = silent
# @vicinae.icon = 💾
# @vicinae.packageName = Panels
# @vicinae.keywords = ["usb", "eject"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call bar open drives
