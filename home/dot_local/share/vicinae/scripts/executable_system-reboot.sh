#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Reboot
# @vicinae.mode silent
# @vicinae.icon 🔄
# @vicinae.packageName System
# @vicinae.keywords ["restart"]
# @vicinae.needsConfirmation true
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec systemctl reboot
