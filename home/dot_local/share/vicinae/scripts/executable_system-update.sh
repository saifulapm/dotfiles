#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Update Everything
# @vicinae.mode silent
# @vicinae.icon ⬆️
# @vicinae.packageName System
# @vicinae.keywords ["dnf", "upgrade"]
set -euo pipefail
# A failed update must not close looking like a success (omarchy bc0753df):
# carry the exit code into a red "failed" prompt, green "done" otherwise.
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc "just -f "$HOME/.dotfiles/justfile" update-all; code=\$?; if (( code == 0 )); then printf '\n\033[32m● \033[0mdone — press enter to close'; else printf '\n\033[31m● \033[0mfailed (exit code %d) — press enter to close' \$code; fi; read -r"
