#!/usr/bin/env bash
# Mod+/ shows every titled niri bind, each surface's own keys and the touchpad's gestures in six groups inside the island, and Esc gives the keyboard back.
{
source "$(dirname "$0")/lib.sh"

sheet_state() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
state_is() { sheet_state | jq -e "$@" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_slash() { niri msg action spawn -- dots-call cheatsheet toggle; }
sheet_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# Under the resting island at the top centre, where the sheet's rows draw; a dead shell leaves it as it was.
middle_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 2 | floor) - 200),\(.y + 60) 400x200"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
titled=$(grep -c 'hotkey-overlay-title=' "$DOTS_NIRI_BINDS")
in_surfaces=$(node -e 'import(process.argv[1]).then((m) => console.log(m.IN_SURFACES.length))' "$repo/shell/lib/cheatsheet.mjs")
island_is() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e "$@" >/dev/null; }

until_ok 5000 shell_status >/dev/null
closed_rgb=$(middle_rgb)
drawn() { [ "$(middle_rgb)" != "$closed_rgb" ]; }
sheet_shown() { state_is '.open' && island_is '.surface == "cheatsheet" and .animating == false' && sheet_focus Exclusive && drawn; }
sheet_gone() { state_is '.open == false and .drawing == false' && sheet_focus None && ! drawn; }

mod_slash
until_ok 3000 sheet_shown
check "Mod+/ shows the cheat sheet with exclusive keyboard" sheet_shown
# Each surface's own keys and seven touchpad rows follow the binds: three swipes, two pinches and two corners.
check "state counts $titled rows, one per titled bind, the $in_surfaces in surfaces and the 7 touchpad rows" state_is --argjson n "$((titled + in_surfaces + 7))" '.rows == $n'
check "no row's title is cut short" state_is '.truncated == 0'
check "the drawn rows include the switcher's Alt+Tab key" state_is '.rowKeys | index("⌥ Tab") != null'
check "the drawn rows include the Notes corner" state_is '.rowKeys | index("↗ corner") != null'
check "state lists the six groups" state_is '.groups == ["SURFACES", "IN SURFACES", "WORK", "WINDOWS", "SYSTEM", "TOUCHPAD"]'

wtype -k Escape
until_ok 2000 sheet_gone
check "Esc hides the cheat sheet and releases the keyboard" sheet_gone
check "status lists cheatsheet in loaded" bash -c 'timeout 0.5 qs ipc call shell status | jq -e "any(.loaded[]; . == \"cheatsheet\")" >/dev/null'
check "status reports one timer" bash -c 'timeout 0.5 qs ipc call shell status | jq -e ".timers == 1" >/dev/null'

exit $((fails > 0))
}
