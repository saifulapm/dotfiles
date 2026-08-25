#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Show Clipboard as QR Code
# @vicinae.mode silent
# @vicinae.icon 📱
# @vicinae.packageName Shell
# @vicinae.keywords ["qr", "share", "phone", "clipboard"]
# The clipboard as a scannable QR in a floating imv window — hand a URL or
# a bit of text to a phone without typing it. The capture-qr command is the
# other direction (scan a QR off the screen).
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"

text="$(wl-paste --no-newline --type text 2>/dev/null || true)"
[[ -n $text ]] || { notify-send -a qshell "📱 QR" "Clipboard has no text"; exit 0; }
types="$(wl-paste --list-types 2>/dev/null || true)"
if grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
    notify-send -a qshell "📱 QR" "Clipboard is marked sensitive — skipped"
    exit 0
fi
# QR alphanumeric capacity tops out well below this; binary mode caps ~2900.
if ((${#text} > 2000)); then
    notify-send -a qshell "📱 QR" "Clipboard too large for a QR (${#text} chars)"
    exit 0
fi

out="${XDG_RUNTIME_DIR:-/tmp}/qshell-clipboard-qr.png"
qrencode -s 10 -m 2 -o "$out" -- "$text"
# imv already has a floating window-rule in niri; app-run keeps the viewer
# out of vicinae's cgroup.
exec app-run imv "$out"
