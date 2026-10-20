#!/usr/bin/env bash
# Mod+. opens the launcher in emoji mode, typing fire finds the emoji, and Enter copies it and types it into the window you came from.
{
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_period() { niri msg action spawn -- dots-call launcher mode emoji; }
# Keys typed before niri moves the keyboard to the launcher go to the window behind, so the check waits for that window to lose focus.
keyboard_taken() { state_is ".open and .mode == \"emoji\"" && ! foot_focused; }

until_ok 5000 shell_status >/dev/null

typed=$(mktemp -u)
cleanup() { rm -f "$typed"; }
niri msg action spawn -- foot -c /dev/null -e sh -c "read x; echo \"\$x\" > $typed"
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .is_focused and .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_focused

mod_period
until_ok 3000 keyboard_taken
wtype fire
until_ok 3000 state_is '.mode == "emoji" and .query == ": fire" and .results[0] == "🔥 fire"'
check "typing fire lists the fire emoji first" state_is '.mode == "emoji" and .results[0] == "🔥 fire"'
wtype -k Return
pasted() { [ "$(wl-paste 2>/dev/null)" = 🔥 ]; }
until_ok 3000 pasted
check "Enter puts the emoji on the clipboard" pasted
until_ok 2000 state_is '.open == false'
# The launcher types after it gives the keyboard back, so the check waits before ending foot's line.
sleep 0.5
wtype -k Return
typed_ok() { [ "$(cat "$typed" 2>/dev/null)" = 🔥 ]; }
until_ok 3000 typed_ok
check "Enter types the emoji into the foot it came from" typed_ok

exit $((fails > 0))
}
