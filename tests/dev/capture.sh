#!/usr/bin/env bash
# A capture stores the primary selection in the active section, says so in the island, and leaves the clipboard alone.
source "$(dirname "$0")/lib.sh"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$1" >/dev/null; }
island_says() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e --arg t "$1" '.mode == "toast" and .text == $t' >/dev/null; }
island_rests() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e '.mode == "rest"' >/dev/null; }
store_has() { jq -e "$1" "$store" >/dev/null 2>&1; }
capture() { timeout 0.5 qs ipc call notes capture >/dev/null 2>&1; }
store="$DOTS_DEV_DIR/data/dots/notes/dev.json"

until_ok 5000 notes_is '.count == 0'
wl-copy 'clip before'
wl-copy --primary 'hello capture'
until_ok 2000 test "$(wl-paste --primary)" = 'hello capture'
before=$(wl-paste)

capture
until_ok 2000 notes_is '.count == 1'
check "a capture adds the selection as a note in the active section" notes_is '.count == 1 and ([.notes[] | select(.deleted | not)][0] | .text == "hello capture") and .notes[0].section == .activeSection'
check "the island says Captured" until_ok 1000 island_says Captured
check "the clipboard is unchanged" test "$(wl-paste)" = "$before"
check "the note is in the store file" store_has '.notes[0].text == "hello capture"'
t0=$(now_ms)
until_ok 3000 island_rests
held=$(($(now_ms) - t0))
check "the toast is gone within 2 s ($held ms)" test "$held" -lt 2000

capture
check "the same selection again says Already captured" until_ok 1000 island_says 'Already captured'
check "and adds no note" notes_is '.count == 1'

wl-copy --primary --clear
until_ok 2000 bash -c '! wl-paste --primary >/dev/null 2>&1'
capture
check "an empty selection says Nothing selected" until_ok 1000 island_says 'Nothing selected'
check "and adds no note" notes_is '.count == 1'

wl-copy --primary "$(printf 'x%.0s' $(seq 12000))"
capture
until_ok 2000 notes_is '.count == 2'
check "a 12,000-character selection is stored as 10,000" notes_is '[.notes[] | .text | length] | max == 10000'

printf '{"notes": [' >"$store"
wl-copy --primary 'after the store broke'
sleep 0.3
capture
check "a store that does not parse is never saved over" until_ok 1000 island_says 'Notes store unreadable'
check "and the file is as it was" test "$(cat "$store")" = '{"notes": ['

exit $((fails > 0))
