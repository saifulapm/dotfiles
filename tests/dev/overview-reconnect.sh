#!/usr/bin/env bash
# niri drops an event stream that falls 64 events behind; the shell connects again, rebuilds its state and still lets go of the keyboard when the overview closes.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
dropped() { grep -q "reading events too slowly" "$dev_log"; }

niri msg action spawn -- foot -c /dev/null
foot_open() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_open
niri msg action open-overview
until_ok 2000 surfaces_focus Exclusive

# A frozen shell reads nothing, so each workspace switch's small events fill its socket and then niri's queue.
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
kill -STOP "$pid"
for _ in $(seq 400); do
  niri msg action focus-workspace-down
  niri msg action focus-workspace-up
  dropped && break
done
kill -CONT "$pid"
check "niri dropped the frozen shell's event stream" dropped

# The stream's first burst says the overview is open, so the shell takes the keys again.
until_ok 3000 surfaces_focus Exclusive
wtype -k Shift_L
wtype c
until_ok 2000 launcher_is '.open and .query == "c"'
check "after the drop, c in the overview still opens the launcher" launcher_is '.open and .query == "c"'
timeout 0.5 qs ipc call launcher close

niri msg action close-overview
until_ok 2000 surfaces_focus None
check "closing the overview after the drop gives the keyboard back" surfaces_focus None

exit $((fails > 0))
}
