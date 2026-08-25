#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Polish Clipboard Text
# @vicinae.mode silent
# @vicinae.icon ✍️
# @vicinae.packageName AI
# @vicinae.keywords ["grammar", "fix", "rewrite", "spelling", "english"]
# Fix grammar/spelling of whatever is in the clipboard, keeping tone and
# meaning, and put the corrected text back on the clipboard. Ported idea:
# the omarchy text-polish/proofreader plugin cluster (10+ variants), done
# with the claude CLI already on this machine — no new dependencies.
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Byte-truncate WITHOUT splitting a UTF-8 codepoint — head -c on Bangla text
# produced invalid UTF-8 that notify-send rejects (found in testing). iconv
# -c drops the mangled trailing bytes.
preview() { head -c "$1" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null; }

text="$(wl-paste --no-newline --type text 2>/dev/null || true)"
[[ -n $text ]] || { notify-send -a qshell "✍️ Polish" "Clipboard has no text"; exit 0; }
# Never send a password manager's copy to an AI. Herestring, not a pipe:
# grep -q + pipefail is the SIGPIPE trap (see bin/clipboard-sync-push).
types="$(wl-paste --list-types 2>/dev/null || true)"
if grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
    notify-send -a qshell "✍️ Polish" "Clipboard is marked sensitive — skipped"
    exit 0
fi
if ((${#text} > 8000)); then
    notify-send -a qshell "✍️ Polish" "Clipboard too large (${#text} chars)"
    exit 0
fi

notify-send -a qshell -t 5000 "✍️ Polishing…" "$(preview 80 <<<"$text")"
result="$(claude --model haiku -p "Fix the grammar, spelling and punctuation of the following text. Keep the author's tone, language, formatting and meaning. Reply with ONLY the corrected text — no commentary, no surrounding quotes:

$text" 2>/dev/null)" || { notify-send -a qshell "✍️ Polish" "claude failed — is it logged in?"; exit 1; }
[[ -n $result ]] || { notify-send -a qshell "✍️ Polish" "Empty result"; exit 1; }

printf '%s' "$result" | wl-copy
notify-send -a qshell "✍️ Polished — copied" "$(preview 160 <<<"$result")"
