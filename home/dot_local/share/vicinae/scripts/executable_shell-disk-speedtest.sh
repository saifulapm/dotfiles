#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Disk Speed Test
# @vicinae.mode silent
# @vicinae.icon 💽
# @vicinae.packageName Shell
# @vicinae.keywords ["benchmark"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec qs ipc call diskspeedtest -- show
