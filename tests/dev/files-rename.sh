#!/usr/bin/env bash
# Files' r renames the cursor row with its extension kept, a makes a folder, d trashes the marked files after asking; a taken name is refused, never overwritten.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads"
printf 'invoice' >"$h/Downloads/invoice-0912.pdf"
printf 'old notes' >"$h/Downloads/notes.txt"
for n in IMG_2039.jpg IMG_2040.jpg; do : >"$h/Downloads/$n"; done
log=$work/files.log

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
# The nested session's XDG_DATA_HOME is a temp dir, so this is its own trash, never the live one.
trashed() { trash-list 2>/dev/null | grep -c "$h/Downloads/$1\$"; }

niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
# Keys typed before niri focuses the new window go nowhere.
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .is_focused)' >/dev/null"
wtype /down
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'

wtype /0912
wtype -k Return
until_ok 1000 files_is '.cursor == "invoice-0912.pdf" and .finding == false'
wtype r
until_ok 1000 files_is '.renaming'
check "r on invoice-0912.pdf selects invoice-0912 ($(files_state | jq -c .renameSelected))" files_is '.renameSelected == "invoice-0912"'
wtype invoice-0913
wtype -k Return
until_ok 2000 files_is '.renaming == false and .cursor == "invoice-0913.pdf"'
check "typing invoice-0913 and Enter renames it to invoice-0913.pdf, the cursor on it" \
  bash -c "[ -f '$h/Downloads/invoice-0913.pdf' ] && [ ! -e '$h/Downloads/invoice-0912.pdf' ] && [ \"\$(cat '$h/Downloads/invoice-0913.pdf')\" = invoice ]"

wtype r
until_ok 1000 files_is '.renaming'
wtype -M ctrl a -m ctrl
wtype notes.txt
wtype -k Return
until_ok 1000 files_is '.renaming == false and .notice != ""'
check "renaming it to notes.txt, a name taken, is refused on the status line ($(files_state | jq -c .notice))" \
  bash -c "timeout 0.5 qs ipc -p '$files_qml' call files state | jq -e '.notice == \"notes.txt exists\"' >/dev/null && [ \"\$(cat '$h/Downloads/notes.txt')\" = 'old notes' ] && [ -f '$h/Downloads/invoice-0913.pdf' ]"
wtype r
until_ok 1000 files_is '.renaming'
wtype -k Escape
until_ok 1000 files_is '.renaming == false'
check "Esc leaves the name as it was" bash -c "[ -f '$h/Downloads/invoice-0913.pdf' ]"

wtype a
until_ok 1000 files_is '.asking == "mkdir"'
wtype receipts
wtype -k Return
until_ok 2000 files_is '.asking == "" and .cursor == "receipts"'
check "a makes the folder receipts, the cursor on it" bash -c "[ -d '$h/Downloads/receipts' ]"

wtype /IMG
wtype -k Return
until_ok 1000 files_is '.rows == ["IMG_2039.jpg", "IMG_2040.jpg"] and .finding == false'
wtype -k space -k space
until_ok 1000 files_is '(.marked | length) == 2'
wtype d
until_ok 1000 files_is '.asking == "trash"'
check "d on two marked files asks first ($(files_state | jq -c .ask))" files_is '.ask == "trash 2 files · ↵ trash · esc keep"'
wtype -k Escape
until_ok 1000 files_is '.asking == ""'
check "Esc keeps them" bash -c "[ -f '$h/Downloads/IMG_2039.jpg' ] && [ -f '$h/Downloads/IMG_2040.jpg' ]"
wtype d
until_ok 1000 files_is '.asking == "trash"'
wtype -k Return
until_ok 3000 bash -c "[ ! -e '$h/Downloads/IMG_2039.jpg' ] && [ ! -e '$h/Downloads/IMG_2040.jpg' ]"
check "Enter moves both to the trash, where trash-list shows them ($(trashed IMG_2039.jpg) and $(trashed IMG_2040.jpg))" \
  test "$(trashed IMG_2039.jpg)" = 1 -a "$(trashed IMG_2040.jpg)" = 1

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
