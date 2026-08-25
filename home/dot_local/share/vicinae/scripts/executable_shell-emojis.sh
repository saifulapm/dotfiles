#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Emoji Picker
# @vicinae.mode = silent
# @vicinae.icon = 😀
# @vicinae.packageName = Shell
# @vicinae.keywords = ["emoji"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call emojis toggle
