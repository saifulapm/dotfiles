#!/usr/bin/env bash
# @vicinae.schemaVersion = 1
# @vicinae.title = Set Timezone
# @vicinae.mode = silent
# @vicinae.icon = 🌐
# @vicinae.packageName = Setup
# @vicinae.keywords = ["tz"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec foot-run --app-id=qshell-float -e bash -lc 'timezone-set'
