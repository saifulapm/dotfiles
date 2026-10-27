#!/usr/bin/env bash
# A shell restarted while niri's overview is open learns it from the event stream's first burst and takes the keys.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }

niri msg action spawn -- foot -c /dev/null
foot_open() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_open
niri msg action open-overview
until_ok 2000 surfaces_focus Exclusive

t0=$(now_ms)
systemctl --user restart "$DOTS_DEV_UNIT"
# niri can list the old shell's layer for a moment after its process ends.
no_surfaces() { niri msg -j layers | jq -e 'all(.[]; .namespace != "dots-surfaces")' >/dev/null; }
until_ok 2000 no_surfaces
until_ok 10000 surfaces_focus Exclusive
ms=$(($(now_ms) - t0))
check "the restarted shell holds the keyboard ${ms} ms after the restart" surfaces_focus Exclusive
check "within 1.2 s, without the warm-up's second" test "$ms" -le 1200
check "with the overview still open" overview_is true

wtype -k Shift_L
wtype c
until_ok 2000 launcher_is '.open and .query == "c"'
check "c opens the launcher reading c ($(launcher_state | jq -c .query))" launcher_is '.open and .query == "c"'

exit $((fails > 0))
}
