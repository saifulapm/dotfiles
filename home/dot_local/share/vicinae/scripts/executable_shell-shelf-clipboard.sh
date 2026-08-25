#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Add Clipboard to Shelf
# @vicinae.mode silent
# @vicinae.icon 🗄️
# @vicinae.packageName Shell
# @vicinae.keywords ["shelf", "clipboard", "park", "stash"]
# Text becomes a .txt, an image a .png — either way a real, draggable file.
set -euo pipefail
exec qs ipc call shelf addClipboard
