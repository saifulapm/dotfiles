#!/usr/bin/env bash
# Mod+Space opens the launcher, typing filters, Enter starts an app, Esc gives the keyboard back.
{
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_space() { niri msg action spawn -- dots-call launcher toggle; }
launcher_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# An 8 px square in the first result row's top padding, clear of its text and its ↵ badge, as the state places the row.
row_geo() { launcher_state | jq -r '.cursorBox // empty | "\(.x + .w - 70 | floor),\(.y + 4 | floor) 8x8"'; }
# The row is selected while the launcher is open, so it draws the accent's veil over the card's paper, 203 208 230, which the desk there never is.
row_is_tint() {
  local geo r g b
  geo=$(row_geo)
  [ -n "$geo" ] || return 1
  read -r r g b < <(grim -s 1 -t ppm -g "$geo" - | mean_rgb)
  ((r >= 200 && r <= 206 && g >= 205 && g <= 211 && b >= 227 && b <= 233))
}
launcher_mapped() { state_is .open && launcher_focus Exclusive && row_is_tint; }
# Closed, the launcher stays mapped but takes no keyboard and draws nothing.
launcher_gone() { state_is '.open == false' && launcher_focus None && ! row_is_tint; }
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
until_ok 2000 state_is '.legendOverflow == false'
check "the prefix legend fits the card on one line ($(launcher_state | jq -c '[.legendKeys, .legendLines]'))" state_is '.legendKeys == 5 and .legendOverflow == false'
check "status lists launcher in loaded" bash -c 'timeout 0.5 qs ipc call shell status | jq -e "any(.loaded[]; . == \"launcher\")" >/dev/null'
wtype foot
until_ok 3000 state_is '.open and .mode == "apps" and .query == "foot" and .results[0] == "Foot" and .selected == 0'
check "typing foot puts Foot first" state_is '.query == "foot" and .results[0] == "Foot"'
check "Foot's row carries its theme icon, looked up when the shell scanned it ($(launcher_state | jq -c '.icons[0]'))" state_is '.icons[0] | test("^image://icon/foot")'
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
cleanup() { rm -f "$typed"; }
before=$(niri msg -j windows | jq '[.[].id]')
niri msg action spawn -- foot -c /dev/null -e sh -c "read x; echo \"\$x\" > $typed"
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
}
