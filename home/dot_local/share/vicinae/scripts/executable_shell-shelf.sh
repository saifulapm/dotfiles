#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Shelf
# @vicinae.mode silent
# @vicinae.icon 🗄️
# @vicinae.packageName Shell
# @vicinae.keywords ["shelf", "dropzone", "ledge", "files", "park"]
set -euo pipefail
exec qs ipc call shelf toggle
