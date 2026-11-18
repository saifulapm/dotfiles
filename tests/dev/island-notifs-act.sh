#!/usr/bin/env bash
# In the island's notification centre the selected tile shows its buttons, the first inverted, and Enter runs it; / searches; a sender's control and bidi characters never draw; forty notifications stop at the output's height less 48 px and the list scrolls.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
notifs_is() { notifs | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_a() { niri msg action spawn -- dots-call notifs toggle; }
open_centre() {
  mod_a
  until_ok 3000 island_is '.surface == "notifs" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 notifs_is '.keyboard and .settled'
}
close_centre() {
  wtype -k Escape
  until_ok 3000 at_rest
}

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest

# notify-send -A waits for the action and prints the one invoked, so it runs in the background into a file.
picked=$DOTS_DEV_DIR/picked
notify-send -a Mail -A open=Open -A later=Later "Ask" "pick one" >"$picked" 9>&- &
until_ok 2000 notifs_is '.count == 1'
until_ok 8000 island_is '.mode == "rest"'
open_centre
echo "     actions: $(notifs | jq -c .actions)"
check "the selected tile shows Open inverted, then Later" notifs_is '[.actions[] | [.text, .inverted]] == [["Open", true], ["Later", false]] and .actions[0].fill != .actions[1].fill'
wtype -k Return
until_ok 3000 at_rest
until_ok 3000 test -s "$picked"
check "Enter ran Open ($(cat "$picked"))" grep -qx open "$picked"

notify-send -a Mail "One"
notify-send -a Mail "Two"
# A summary holding U+202E and an ESC character.
notify-send -a Mail "$(printf 'evil‮\x1b[31m done')"
until_ok 2000 notifs_is '.count == 4'
until_ok 8000 island_is '.mode == "rest"'
open_centre
check "the summary draws without U+202E or ESC ($(notifs | jq -c '[.notes[].summary]'))" notifs_is '[.notes[].summary] | any(. == "evil[31m done") and all(test("[‮\u001b]") | not)'
wtype /
sleep 0.2
wtype two
until_ok 2000 notifs_is '.query == "two"'
check "/ then two leaves only Two ($(notifs | jq -c '{groups, countText}'))" notifs_is '.groups == [{app: "Mail", entries: ["Two"]}] and .countText == "1 of 4"'
wtype -k Escape
until_ok 1000 notifs_is '.query == "" and .searching == false'
check "Esc in the search clears it and leaves the centre open ($(notifs | jq -c '{query, open, countText}'))" notifs_is '.open and .countText == "4"'
close_centre

# Forty notifications from one app: the island stops at the output's height less 48 px, and moving down scrolls the list.
read -r _ oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
for i in $(seq 1 40); do notify-send -a Bulk "bulk $i"; done
until_ok 5000 notifs_is '.count == 44'
until_ok 15000 island_is '.mode == "rest"'
open_centre
check "with 44 notifications the island is $((oh - 48)) px tall ($(island | jq -c '{height}'))" island_is --argjson h $((oh - 48)) '.height == $h'
check "the list holds more than it shows ($(notifs | jq -c '{contentHeight, h: .listBox.h}'))" notifs_is '.contentHeight > .listBox.h'
check "it opens at the top, the first app's head in view ($(notifs | jq -c '{scrollY}'))" notifs_is '.scrollY == 0'
for _ in $(seq 1 30); do wtype -k j; sleep 0.05; done
until_ok 2000 notifs_is '.scrollY > 0'
check "moving down scrolls the list ($(notifs | jq -c '{selected, scrollY}'))" notifs_is '.scrollY > 0'
close_centre
# Reopened after a scroll, it opens at the top again.
open_centre
check "reopened, it opens at the top again ($(notifs | jq -c '{scrollY}'))" notifs_is '.scrollY == 0'
close_centre

# A 300-character button label elides inside its tile, and the next button stays on the island.
timeout 0.5 qs ipc call notifs clear >/dev/null
long=$(printf 'L%.0s' {1..300})
notify-send -a Long -A "long=$long" -A second=Second "Long" >/dev/null 9>&- &
long_sender=$!
until_ok 2000 notifs_is '.count == 1'
until_ok 8000 island_is '.mode == "rest"'
open_centre
fit() { notifs | jq -e '.notes[0].box as $t | all(.actions[]; .x >= $t.x and .x + .w <= $t.x + $t.w)' >/dev/null; }
check "both buttons stay inside the tile ($(notifs | jq -c '[.notes[0].box, [.actions[] | {x, w}]]'))" fit
close_centre
kill "$long_sender" 2>/dev/null
exit "$fails"
}
