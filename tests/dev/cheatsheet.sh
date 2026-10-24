#!/usr/bin/env bash
# Mod+/ shows every titled niri bind and the touchpad's gestures in five groups, and Esc gives the keyboard back.
{
source "$(dirname "$0")/lib.sh"

sheet_state() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
state_is() { sheet_state | jq -e "$@" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_slash() { niri msg action spawn -- dots-call cheatsheet toggle; }
sheet_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# The middle of the screen, where the card's rows draw; a dead shell leaves it as it was.
middle_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 2 | floor) - 200),\(.y + (.height / 2 | floor) - 100) 400x200"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
titled=$(grep -c 'hotkey-overlay-title=' "$DOTS_NIRI_BINDS")

until_ok 5000 shell_status >/dev/null
closed_rgb=$(middle_rgb)
drawn() { [ "$(middle_rgb)" != "$closed_rgb" ]; }
sheet_shown() { state_is '.open and .settled' && sheet_focus Exclusive && drawn; }
sheet_gone() { state_is '.open == false and .drawing == false' && sheet_focus None && ! drawn; }

mod_slash
until_ok 3000 sheet_shown
check "Mod+/ shows the cheat sheet with exclusive keyboard" sheet_shown
# Seven touchpad rows follow the binds: three swipes, two pinches and two corners.
check "state counts $titled rows, one per titled bind, and the 7 touchpad rows" state_is --argjson n "$((titled + 7))" '.rows == $n'
check "no row's title is cut short" state_is '.truncated == 0'
check "the drawn rows include the switcher's Alt+Tab key" state_is '.rowKeys | index("⌥ TAB") != null'
check "the drawn rows include the Notes corner" state_is '.rowKeys | index("↗ CORNER") != null'
check "state lists the five groups" state_is '.groups == ["SURFACES", "WORK", "WINDOWS", "SYSTEM", "TOUCHPAD"]'

wtype -k Escape
until_ok 2000 sheet_gone
check "Esc hides the cheat sheet and releases the keyboard" sheet_gone
check "status lists cheatsheet in loaded" bash -c 'timeout 0.5 qs ipc call shell status | jq -e "any(.loaded[]; . == \"cheatsheet\")" >/dev/null'
check "status reports one timer" bash -c 'timeout 0.5 qs ipc call shell status | jq -e ".timers == 1" >/dev/null'

exit $((fails > 0))
}
