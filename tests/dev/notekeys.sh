#!/usr/bin/env bash
# Sections, tags, search, merge, move, delete, done and edit all work from the keys in Notes.
source "$(dirname "$0")/lib.sh"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$1" >/dev/null; }
notes_focused() { niri msg -j windows | jq -e 'any(.[]; .title == "Notes" and .is_focused)' >/dev/null; }
note() { notes_state | jq -c --arg t "$1" '[.notes[] | select(.text == $t)][0]'; }
# Types a note in the composer and waits for the store to hold it.
compose() {
  local n
  n=$(notes_state | jq '.notes | length')
  wtype "$1"
  wtype -k Return
  until_ok 2000 notes_is "(.notes | length) > $n"
}
key() { wtype "$@"; sleep 0.1; }

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
niri msg action spawn -- qs ipc call notes toggle
until_ok 3000 notes_focused

wtype '# prompts'
wtype -k Return
until_ok 2000 notes_is '.section == "prompts"'
check "composing # prompts makes prompts the active section" notes_is '.activeSection == "prompts" and .count == 0'
wl-copy --primary 'captured into prompts'
timeout 0.5 qs ipc call notes capture
until_ok 2000 notes_is '.count == 1'
check "the next capture lands in prompts" notes_is '.notes[0].section == "prompts"'

compose a
compose b
compose 'the island grows down'
key -k Tab
check "Tab moves to the list, newest first" notes_is '.mode == "list" and (.selected as $s | .notes[] | select(.id == $s) | .text) == "the island grows down"'
# The list is newest first: the island note, b, a, then the capture.
key j
key j
key v
key k
key v
check "v picks a, then b" notes_is '(.marked | length) == 2'
key m
until_ok 2000 notes_is '.count == 3'
check "m merges a and b into one note a\n\nb" notes_is '[.notes[] | select(.deleted | not) | .text] | index("a\n\nb") != null'
check "the other note is a tombstone" notes_is '[.notes[] | select(.deleted)] | length == 1 and .[0].text == ""'

key -M ctrl k -m ctrl
until_ok 1000 notes_is '.mode == "picker" and .picking == "switch"'
key inbox
key -k Return
until_ok 1000 notes_is '.activeSection == "inbox" and .mode == "list"'
check "Ctrl+K switches to inbox" notes_is '.activeSection == "inbox" and .cards == []'
key -k Tab
compose 'island in the inbox'
key -k Tab

key /
key island
until_ok 1000 notes_is '.query == "island"'
check "/island shows only island notes, across sections" notes_is '([.cards[] as $id | .notes[] | select(.id == $id) | .section] | unique) == ["inbox", "prompts"] and (.cards | length) == 2'
key -k Return
key 3
sel=$(notes_state | jq -r .selected)
check "3 tags the note yellow" until_ok 1000 notes_is '.notes[] | select(.id == "'"$sel"'") | .tags == ["yellow"]'
key 3
check "3 again takes the tag off" until_ok 1000 notes_is '.notes[] | select(.id == "'"$sel"'") | .tags == []'
key -k space
check "Space makes it a to-do" until_ok 1000 notes_is '.notes[] | select(.id == "'"$sel"'") | .todo and (.done | not)'
key -k space
check "Space again marks it done" until_ok 1000 notes_is '.notes[] | select(.id == "'"$sel"'") | .done'
key -k Escape
until_ok 1000 notes_is '.query == ""'

key -M shift m -m shift
until_ok 1000 notes_is '.mode == "picker" and .picking == "move"'
key later
key -k Return
until_ok 1000 notes_is '.mode == "list"'
check "M moves the selected note to a new section later" notes_is '.sections == ["inbox", "prompts", "later"] and (.notes[] | select(.id == "'"$sel"'") | .section) == "later"'

key -M ctrl k -m ctrl
key prompts
key -k Return
until_ok 1000 notes_is '.activeSection == "prompts" and .mode == "list"'
key -k Return
until_ok 1000 notes_is '.mode == "composer" and .editing != ""'
key -M ctrl a -m ctrl
key 'edited'
key -k Return
until_ok 1000 notes_is '.mode == "list" and .editing == ""'
check "Enter edits the selected note" notes_is '[.notes[] | select(.text == "edited")] | length == 1'
n=$(notes_state | jq '.count')
key d
until_ok 1000 notes_is ".count == $((n - 1))"
check "d deletes it, leaving a tombstone" notes_is '[.notes[] | select(.deleted)] | length == 2'

pick_section() {
  key -M ctrl k -m ctrl
  until_ok 1000 notes_is '.mode == "picker"'
  key "$1"
  [ -z "${2:-}" ] || key -k "$2"
  key -k Return
  until_ok 1000 notes_is '.mode == "list"'
}
pick_section homework
pick_section work Down
check "a typed name that only partly matches can still make its own section" notes_is '.activeSection == "work"'
pick_section inbox
pick_section work
check "an exact section name wins over one that contains it" notes_is '.activeSection == "work"'

exit $((fails > 0))
