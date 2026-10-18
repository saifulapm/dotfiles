#!/usr/bin/env bash
# Mod+Space opens the launcher, typing filters, Enter starts an app, Esc gives the keyboard back.
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_space() { niri msg action spawn -- qs ipc call launcher toggle; }
launcher_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-launcher" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# The first result row, selected and ink while the launcher is open.
row_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 2 | floor) - 5),\(.y + 257) 10x10"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
row_is_ink() { local r g b; read -r r g b < <(row_rgb); ((r < 60 && g < 60 && b < 60)); }
launcher_mapped() { state_is .open && launcher_focus Exclusive && row_is_ink; }
# Closed, the launcher stays mapped but takes no keyboard and draws nothing.
launcher_gone() { state_is '.open == false' && launcher_focus None && ! row_is_ink; }
foot_open() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }
# Waits for open number $1 to report its time, and prints it.
open_ms() {
  until_ok 3000 state_is ".opens == $1 and (.openMs | type) == \"number\"" || { echo "none"; return; }
  launcher_state | jq -r .openMs
}

until_ok 5000 shell_status >/dev/null
check "no window is open yet" test "$(niri msg -j windows | jq length)" = 0

mod_space
until_ok 3000 launcher_mapped
check "Mod+Space shows the launcher with exclusive keyboard" launcher_mapped
ms1=$(open_ms 1)
check "status lists launcher in loaded" bash -c 'timeout 0.5 qs ipc call shell status | jq -e "any(.loaded[]; . == \"launcher\")" >/dev/null'
wtype foot
until_ok 3000 state_is '.open and .mode == "apps" and .query == "foot" and .results[0] == "Foot" and .selected == 0'
check "typing foot puts Foot first" state_is '.query == "foot" and .results[0] == "Foot"'
wtype -k Return
until_ok 5000 foot_open
check "Enter opens a window with app_id foot" foot_open
until_ok 2000 launcher_gone
check "launching closes the launcher" launcher_gone

mod_space
until_ok 3000 launcher_mapped
ms2=$(open_ms 2)
wtype -k Escape
until_ok 2000 launcher_gone
check "Esc hides the launcher and releases the keyboard" launcher_gone
check "state says open false" state_is '.open == false'

typed=$(mktemp -u)
trap 'dev_stop; rm -f "$dev_out" "$dev_log" "$typed"' EXIT
before=$(niri msg -j windows | jq '[.[].id]')
niri msg action spawn -- foot -e sh -c "read x; echo \"\$x\" > $typed"
new_focused() { niri msg -j windows | jq -e --argjson b "$before" 'any(.[]; .is_focused and (.id | IN($b[]) | not))' >/dev/null; }
until_ok 5000 new_focused
mod_space
until_ok 3000 launcher_mapped
ms3=$(open_ms 3)
wtype -k Escape
until_ok 2000 launcher_gone
wtype ok
wtype -k Return
typed_ok() { [ "$(cat "$typed" 2>/dev/null)" = ok ]; }
until_ok 3000 typed_ok
check "after Esc, typing ok reaches the focused foot" typed_ok

echo "     openMs: first $ms1, second $ms2, third $ms3"
check "state counts at least two opens" state_is '.opens >= 2'
check "the second open reported a numeric openMs" test "$ms2" != none

exit $((fails > 0))
