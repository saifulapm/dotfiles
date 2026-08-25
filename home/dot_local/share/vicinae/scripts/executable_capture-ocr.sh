#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Extract Text (OCR)
# @vicinae.mode silent
# @vicinae.icon 🔤
# @vicinae.packageName Capture
# @vicinae.keywords ["text", "tesseract"]
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"
exec screenshot-ocr
