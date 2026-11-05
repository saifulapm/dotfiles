#!/usr/bin/env bash
# The notification centre by mouse: a click on a row runs its default action as Enter does and closes the centre; a wheel notch scrolls the list and j still brings the selected row into view; a pointer resting on a row never moves the selection.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

out=$DOTS_DEV_DIR/printed
: >"$out"
sender=
cleanup() {
  pointer_stop
  [ -z "$sender" ] || kill "$sender" 2>/dev/null
}

notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
centre_is() { notifs | jq -e "$@" >/dev/null 2>&1; }
island_rest() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e '.mode == "rest"' >/dev/null; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns Mod+A's command through niri.
open_centre() {
  niri msg action spawn -- dots-call notifs toggle
  until_ok 3000 centre_is '.open and .settled' || return 1
  until_ok 2000 focus_is Exclusive
}
closed() { centre_is '.open == false'; }
printed() { [ "$(cat "$out")" = "$1" ]; }
# The selected row lies wholly inside the list's drawn box.
in_view() { centre_is '.cursorBox.y >= .listBox.y and .cursorBox.y + .cursorBox.h <= .listBox.y + .listBox.h'; }

until_ok 5000 shell_status >/dev/null

# notify-send -A waits for an action and prints its key; the newer row, with no action, is the one selected.
notify-send -a T -A default=Open -A later=Later older >"$out" &
sender=$!
until_ok 2000 centre_is '.count == 1'
notify-send -a T newer
until_ok 2000 centre_is '.count == 2'
# A toast on the island would take a click meant for the centre, so they leave first.
until_ok 15000 island_rest
open_centre
check "the centre lists newer then older, newer selected ($(notifs | jq -c '{selected, groups}'))" centre_is '.selected == 0 and .groups == [{app: "T", entries: ["newer", "older"]}]'
click_box notif-row:1
until_ok 2000 printed default
check "a click on the older row runs its default action ($(cat "$out"))" printed default
until_ok 2000 closed
check "and closes the centre" closed
kill "$sender" 2>/dev/null
wait "$sender" 2>/dev/null
sender=

# A press that moves a few pixels and lets go short of the drag threshold is a click, not a drop.
: >"$out"
notify-send -a T -A default=Open -A later=Later jittered >"$out" &
sender=$!
until_ok 2000 centre_is '.count == 2'
until_ok 15000 island_rest
open_centre
read -r jx jy < <(shell_spot notif-row:0)
point press "$jx" "$jy"
point move "$((jx + 4))" "$((jy + 3))" 2
point release
until_ok 2000 printed default
check "a press moved 4 px and let go short of the drag threshold runs the row as a click ($(cat "$out"))" printed default
until_ok 2000 closed
kill "$sender" 2>/dev/null
wait "$sender" 2>/dev/null
sender=

timeout 0.5 qs ipc call notifs clear >/dev/null
for i in $(seq 1 20); do notify-send -a bulk "bulk $i"; done
until_ok 5000 centre_is '.count == 20'
open_centre
check "twenty rows open at the top, the first selected ($(notifs | jq -c '{selected, scrollY}'))" centre_is '.selected == 0 and .scrollY == 0'
wheel_box notif-row:2 1
until_ok 1000 centre_is '.scrollY != 0'
check "one wheel notch down moves the list 60 px and leaves the selection ($(notifs | jq -c '{selected, scrollY}'))" centre_is '.scrollY == 60 and .selected == 0'
wtype j
until_ok 1000 centre_is '.selected == 1'
check "then j selects the second row ($(notifs | jq -c '{selected, scrollY}'))" centre_is '.selected == 1'
check "and it is in view ($(notifs | jq -c '{cursorBox, listBox}'))" in_view

point wheel 4
until_ok 1000 centre_is '.scrollY == 300'
check "four more notches move the list to 300 px, past the selected row ($(notifs | jq -c '{selected, scrollY}'))" centre_is '.scrollY == 300 and .selected == 1'
wtype j
until_ok 1000 centre_is '.selected == 2'
check "j selects the third row ($(notifs | jq -c '{selected, scrollY}'))" centre_is '.selected == 2 and .scrollY < 300'
check "and brings it back into view ($(notifs | jq -c '{cursorBox, listBox}'))" in_view

at=$(shell_spot notif-row:5)
# shellcheck disable=SC2086
point move $at
wtype j
until_ok 1000 centre_is '.selected != 2'
sleep 0.3
check "with the pointer resting on the sixth row, j moves the selection one row ($(notifs | jq -c .selected))" centre_is '.selected == 3'
check "and the centre stays open" centre_is .open
wtype -k Escape
until_ok 2000 closed

exit $((fails > 0))
}
