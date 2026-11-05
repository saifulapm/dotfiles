#!/usr/bin/env bash
# The launcher by mouse: a click on a row runs it as Enter does, in apps and in the c mode; a wheel notch moves the list three rows; a pointer resting on a row while Saiful types never moves the selection.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$@" >/dev/null 2>&1; }
open_launcher() {
  niri msg action spawn -- dots-call launcher toggle
  until_ok 3000 state_is '.open and .settled' || return 1
  # Keys typed before the launcher has the keyboard go to nothing.
  until_ok 2000 bash -c "niri msg -j layers | jq -e 'any(.[]; .namespace == \"dots-surfaces\" and .keyboard_interactivity == \"Exclusive\")' >/dev/null"
}
closed() { state_is '.open == false'; }

# Three entries of this run's own, each leaving a file named by its title when it runs.
ran=$DOTS_DEV_DIR/ran
mkdir -p "$ran" "$XDG_DATA_HOME/applications"
for n in One Two Three; do
  printf '[Desktop Entry]\nType=Application\nName=Mousetest %s\nExec=touch %s/%s\n' "$n" "$ran" "$n" >"$XDG_DATA_HOME/applications/mousetest-${n,,}.desktop"
done

until_ok 5000 shell_status >/dev/null
open_launcher
wtype mousetest
until_ok 5000 state_is '.query == "mousetest" and (.results | length) == 3'
check "mousetest lists this run's three entries ($(launcher_state | jq -c .results))" state_is '(.results | length) == 3'
third=$(launcher_state | jq -r '.results[2] | sub("^Mousetest "; "")')
click_box launcher-row:2
until_ok 3000 test -e "$ran/$third"
check "a click on the third row runs Mousetest $third ($(ls "$ran" | tr '\n' ' '))" test "$(ls "$ran")" = "$third"
until_ok 2000 closed
check "and closes the launcher" closed

open_launcher
until_ok 2000 state_is '(.results | length) == 8'
wheel_box launcher-row:3 0
check "the pointer rests on the fourth row with the selection on the first" state_is '.selected == 0'
wtype fo
until_ok 2000 state_is '.query == "fo"'
sleep 0.3
check "typing fo under the resting pointer leaves the selection on the first row ($(launcher_state | jq -c '{selected, results}'))" state_is '.selected == 0 and .top == 0'
wtype -k Escape
until_ok 2000 closed

open_launcher
wtype "c "
until_ok 2000 state_is '.mode == "colorschemes" and .count == 40 and .top == 0'
wheel_box launcher-row:4 1
until_ok 1000 state_is '.top != 0'
check "one wheel notch down over the forty colorschemes moves the first shown row by three ($(launcher_state | jq -c '{top, selected}'))" state_is '.top == 3 and (.results | length) == 8'
wheel_box launcher-row:4 -1
until_ok 1000 state_is '.top == 0'
check "and one notch up brings it back ($(launcher_state | jq -c '{top, selected}'))" state_is '.top == 0'
wtype gruv
until_ok 2000 state_is '.query == "c gruv"'
row=$(launcher_state | jq '.results | index("Gruvbox Dark")')
record=$XDG_STATE_HOME/dots/theme-switch.json
rm -f "$record"
click_box "launcher-row:$row"
until_ok 3000 test -s "$record"
check "a click on the Gruvbox Dark row saves gruvbox-dark ($(cat "$XDG_STATE_HOME/dots/theme" 2>/dev/null))" test "$(cat "$XDG_STATE_HOME/dots/theme" 2>/dev/null)" = gruvbox-dark
until_ok 2000 closed
check "and closes the launcher" closed
until_ok 3000 eval "shell_status | jq -e '.theme == \"gruvbox-dark\" and .transition == \"\"' >/dev/null"

exit "$fails"
}
