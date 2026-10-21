#!/usr/bin/env bash
# The launcher's r mode sets a reminder in the state dir, lists what is pending, and d deletes one.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/state/dots/reminders.json"
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
# niri lists the layer Exclusive a moment before its keys arrive, so typing waits until the window has the keyboard.
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
stored() { [ -e "$store" ] && jq -e "$1" "$store" >/dev/null; }

until_ok 5000 shell_status >/dev/null
# The reminders service is the Desk's, which loads after the paper's first frame.
until_ok 10000 desk_up

open_launcher
wtype "r 20m tea"
until_ok 3000 state_is '.mode == "reminder" and .results[0] == "tea"'
check "r 20m tea previews tea" state_is '.mode == "reminder" and .results == ["tea"] and .pending == 0'
wtype -k Return
until_ok 2000 state_is '.open == false'
check "Enter stores it with its id, text, due and created" stored 'length == 1 and .[0].text == "tea" and (.[0].id | type) == "string" and (.[0].due - .[0].created) == 1200000'
check "and closes the launcher" state_is '.open == false'

open_launcher
wtype "r 1h later on"
until_ok 3000 state_is '.results[0] == "later on"'
wtype -k Return
until_ok 2000 stored 'length == 2'

open_launcher
wtype "r "
until_ok 3000 state_is '.mode == "reminder" and (.results | length) == 2'
check "r lists both pending, soonest first" state_is '.results == ["tea", "later on"] and .pending == 2'
check "the first pending row sits under the pending head" state_is '(.heads[0] | test("pending"; "i")) and .heads[1] == ""'
wtype -k Tab
wtype -k j
until_ok 2000 state_is '.selected == 1'
wtype d
until_ok 2000 stored 'length == 1'
check "d on the second row deletes it from reminders.json" stored 'length == 1 and .[0].text == "tea"'
check "and the list shows the one left" state_is '.results == ["tea"] and .pending == 1'
close_launcher

open_launcher
wtype "r 25:00 x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 25:00 x says it cannot set that" state_is '.results[0] | startswith("Cannot set 25:00")'
wtype -k Return
check "Enter stores nothing and keeps the launcher open" bash -c "jq -e 'length == 1' '$store' >/dev/null && timeout 0.5 qs ipc call launcher state | jq -e .open >/dev/null"
close_launcher

open_launcher
wtype "r 0m x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 0m x says it cannot set that" state_is '.results[0] | startswith("Cannot set 0m")'
close_launcher

exit $((fails > 0))
}
