#!/usr/bin/env bash
# A note keeps its text and image: Ctrl+V attaches into the store, y gives the text alone, Y the image, Ctrl+Y the section.
{
source "$(dirname "$0")/lib.sh"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$1" >/dev/null; }
notes_focused() { niri msg -j windows | jq -e 'any(.[]; .title == "Notes" and .is_focused)' >/dev/null; }
island_says() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e --arg t "$1" '.text == $t' >/dev/null; }
types() { wl-paste --list-types 2>/dev/null; }
only_text() { types | grep -q . && ! types | grep -vqE '^(text/plain(;charset=utf-8)?|TEXT|STRING|UTF8_STRING)$'; }
lists_png() { types | grep -qx image/png; }
key() { wtype "$@"; sleep 0.1; }
attachments="$DOTS_DEV_DIR/data/dots/notes/attachments"
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
niri msg action spawn -- dots-call notes toggle
until_ok 3000 notes_focused
wtype 'the island grows down'
wtype -k Return
until_ok 2000 notes_is '.count == 1'
key -k Tab

grim -g '0,0 64x32' "$work/sketch.png"
want=$(sha256sum <"$work/sketch.png" | cut -d' ' -f1)
wl-copy --type image/png <"$work/sketch.png"
key -M ctrl v -m ctrl
until_ok 3000 notes_is '.notes[0].attachments | length == 1'
check "Ctrl+V attaches the clipboard's PNG to the selected note" notes_is '.count == 1 and .notes[0].attachments[0].mime == "image/png"'
check "the attachment is at notes/attachments/<sha256>.png with the original's sha256" test "$(sha256sum <"$attachments/$want.png" | cut -d' ' -f1)" = "$want"
check "the store names it by that sha256" notes_is ".notes[0].attachments[0].sha256 == \"$want\""

key y
until_ok 2000 only_text
check "after y the clipboard lists text only" only_text
check "and pastes the note's text" test "$(wl-paste)" = 'the island grows down'

key -M shift y -m shift
until_ok 2000 lists_png
check "after Y the clipboard lists image/png" lists_png
check "and holds the attached image" test "$(wl-paste --type image/png | sha256sum | cut -d' ' -f1)" = "$want"

key -M ctrl y -m ctrl
until_ok 2000 test "$(wl-paste 2>/dev/null)" = '- the island grows down'
check "Ctrl+Y copies the section as a Markdown list" test "$(wl-paste)" = '- the island grows down'

head -c $((26 * 1024 * 1024)) /dev/zero >"$work/big.png"
wl-copy --type image/png <"$work/big.png"
key -M ctrl v -m ctrl
check "a 26 MB attachment is refused in the island" until_ok 3000 island_says 'Attachment over 25 MB'
check "and nothing is attached" notes_is '.notes[0].attachments | length == 1'
check "and nothing is stored" test "$(find "$attachments" -type f | wc -l)" = 1

exit $((fails > 0))
}
