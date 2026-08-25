#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Translate Clipboard (Bangla ⇄ English)
# @vicinae.mode silent
# @vicinae.icon 🌐
# @vicinae.packageName AI
# @vicinae.keywords ["translate", "bangla", "bengali", "english", "অনুবাদ"]
# Auto-directional translation of the clipboard: Bangla comes back as
# natural English, anything else comes back as natural Bangla. Same
# privacy guards as Polish Clipboard Text.
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Byte-truncate WITHOUT splitting a UTF-8 codepoint — head -c on Bangla text
# produced invalid UTF-8 that notify-send rejects (found in testing). iconv
# -c drops the mangled trailing bytes.
preview() { head -c "$1" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null; }

text="$(wl-paste --no-newline --type text 2>/dev/null || true)"
[[ -n $text ]] || { notify-send -a qshell "🌐 Translate" "Clipboard has no text"; exit 0; }
types="$(wl-paste --list-types 2>/dev/null || true)"
if grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
    notify-send -a qshell "🌐 Translate" "Clipboard is marked sensitive — skipped"
    exit 0
fi
if ((${#text} > 8000)); then
    notify-send -a qshell "🌐 Translate" "Clipboard too large (${#text} chars)"
    exit 0
fi

notify-send -a qshell -t 5000 "🌐 Translating…" "$(preview 80 <<<"$text")"
result="$(claude --model haiku -p "Translate the following text. If it is in Bangla (Bengali), translate it to natural, fluent English. If it is in English or any other language, translate it to natural Bangla. Reply with ONLY the translation — no commentary, no surrounding quotes:

$text" 2>/dev/null)" || { notify-send -a qshell "🌐 Translate" "claude failed — is it logged in?"; exit 1; }
[[ -n $result ]] || { notify-send -a qshell "🌐 Translate" "Empty result"; exit 1; }

printf '%s' "$result" | wl-copy
notify-send -a qshell "🌐 Translated — copied" "$(preview 160 <<<"$result")"
