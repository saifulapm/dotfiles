#!/usr/bin/env bash
# Mod+S opens Notes on Shelf, the first section; a pasted image is a new card at the top that drags out as a file. A drop is covered by shell/lib/notes.test.mjs only, since wtype cannot drag.
{
source "$(dirname "$0")/lib.sh"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$@" >/dev/null; }
notes_focused() { niri msg -j windows | jq -e 'any(.[]; .title == "Notes" and .is_focused)' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_s() { niri msg action spawn -- dots-call notes shelf; }
key() { wtype "$@"; sleep 0.1; }
attachments="$DOTS_DEV_DIR/data/dots/notes/attachments"
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
# A note in inbox first, so Shelf is made after another section and still comes first.
niri msg action spawn -- dots-call notes toggle
until_ok 3000 notes_focused
wtype 'in the inbox'
wtype -k Return
until_ok 2000 notes_is '.count == 1'
key -k Escape
until_ok 2000 notes_is '.open == false'

mod_s
until_ok 3000 notes_focused
check "Mod+S opens and focuses Notes" notes_focused
check "on the Shelf section" notes_is '.open and .section == "Shelf"'
check "and Shelf is the first tab" notes_is '.tabs == ["Shelf", "inbox"]'

grim -g '0,0 64x32' "$work/one.png"
want=$(sha256sum <"$work/one.png" | cut -d' ' -f1)
wl-copy --type image/png <"$work/one.png"
key -M ctrl v -m ctrl
until_ok 3000 notes_is '.count == 2'
check "Ctrl+V adds one card" notes_is '.count == 2 and (.cards | length) == 1'
first=$(notes_state | jq -r '.cards[0]')
check "on Shelf, holding the pasted PNG" notes_is --arg id "$first" --arg sha "$want" '.notes[] | select(.id == $id) | .section == "Shelf" and .attachments[0].sha256 == $sha and .attachments[0].mime == "image/png"'
check "its chip drags out the stored file as a file:// URI" notes_is --arg uri "file://$attachments/$want.png" '.selected == .cards[0] and .offers == [{"text/uri-list": $uri}]'
check "and that file is the pasted PNG" test "$(sha256sum <"$attachments/$want.png" | cut -d' ' -f1)" = "$want"

grim -g '0,0 48x48' "$work/two.png"
wl-copy --type image/png <"$work/two.png"
key -M ctrl v -m ctrl
until_ok 3000 notes_is '.count == 3'
check "a second paste is a second card at the top, not an attachment on the first" notes_is --arg id "$first" '(.cards | length) == 2 and .cards[1] == $id and (.notes[] | select(.id == $id) | .attachments | length) == 1'

mod_s
until_ok 2000 notes_is '.open == false'
check "Mod+S on Shelf closes Notes" notes_is '.open == false'

niri msg action spawn -- dots-call notes toggle
until_ok 3000 notes_focused
key -M ctrl k -m ctrl
wtype 'inbox'
key -k Return
until_ok 2000 notes_is '.section == "inbox"'
mod_s
until_ok 2000 notes_is '.section == "Shelf"'
check "Mod+S from another section switches to Shelf and keeps Notes open" notes_is '.open and .section == "Shelf"'

exit $((fails > 0))
}
