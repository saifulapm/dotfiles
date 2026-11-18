#!/usr/bin/env bash
# Mod+Space grows the island into one 48 px search field; typing lists flat 48 px rows with only the selected one filled, Enter launches, a miss says so, and a key typed in niri's overview opens it there.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
sheet_is() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }
at_rest() { island_is '.surface == null and .width == 176 and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_space() { niri msg action spawn -- dots-call launcher toggle; }
open_launcher() {
  mod_space
  until_ok 3000 island_is '.surface == "launcher" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 launcher_is '.keyboard and .settled'
}
foot_open() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }

until_ok 5000 shell_status >/dev/null
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
until_ok 3000 at_rest
corner_before=$(px 10 $((oh - 10)))
want=$((ow - 48 < 640 ? ow - 48 : 640))

open_launcher
check "Mod+Space sets surface to launcher and the island $want px wide ($(island | jq -c '{surface, width}'))" island_is --argjson w "$want" '.surface == "launcher" and .width == $w'
check "it lists nothing until a key is typed ($(launcher | jq -c .results))" launcher_is '.results == [] and .empty == null'
check "it is one 48 px field reading Search, 80 px tall with no legend row ($(launcher | jq -c .field), $(island | jq .height))" eval 'launcher_is ".field.h == 48 and .field.placeholder == \"Search\"" && island_is ".height == 80"'
check "no veil is drawn: the pixel 10 px in from the bottom left corner is as it was ($(px 10 $((oh - 10))), was $corner_before)" test "$(px 10 $((oh - 10)))" = "$corner_before"

wtype foot
until_ok 3000 launcher_is '.query == "foot" and .results[0] == "Foot"'
check "typing foot lists Foot first ($(launcher | jq -c '.results[:3]'))" launcher_is '.results[0] == "Foot"'
check "its rows are 48 px, and only the first is filled ($(launcher | jq -c '{rowHeights, filled}'))" launcher_is '(.rowHeights | all(. == 48)) and .filled[0] == true and (.filled[1:] | all(. == false))'
t0=$(now_ms)
wtype -k Return
until_ok 1000 island_is '.surface == null'
took=$(($(now_ms) - t0))
check "Enter sets surface to null within 400 ms (${took} ms)" test "$took" -le 400
until_ok 5000 foot_open
check "and opens a foot window" foot_open
until_ok 3000 at_rest

open_launcher
wtype zzzz
until_ok 2000 launcher_is '.query == "zzzz"'
check "zzzz draws No match for 'zzzz' ($(launcher | jq -c .empty))" launcher_is ".empty == \"No match for 'zzzz'\""
wtype -k Escape
until_ok 2000 at_rest
check "Esc returns the island to rest" at_rest

# Typed 50 ms after the key, before the morph settles, every key lands in the field.
mod_space
sleep 0.05
wtype foot # early on purpose
until_ok 2000 launcher_is '.query == "foot"'
check "foot typed 50 ms after Mod+Space reads query foot ($(launcher | jq -c .query))" launcher_is '.query == "foot"'
wtype -k Escape
until_ok 2000 at_rest

niri msg action spawn -- dots-call cheatsheet toggle
until_ok 3000 island_is '.surface == "cheatsheet" and .animating == false'
in_surfaces() { sheet_is '[(.columns[] | select(.name == "IN SURFACES") | .rows[] | select(.surface == "launcher") | .key)] as $k | (["w␣", "v␣", ":␣", "=␣", ">␣", "r␣", "c␣", "Tab", "↵"] - $k | length == 0)'; }
check "IN SURFACES lists the launcher's prefixes and keys" in_surfaces
wtype -k Escape
until_ok 2000 at_rest

niri msg action open-overview
until_ok 2000 surfaces_focus Exclusive
# wtype's first key into a newly focused surface can take the old keymap, so a Shift goes first.
wtype -k Shift_L
wtype f
until_ok 2000 launcher_is '.open and .query == "f"'
check "in the overview, f sets surface to launcher and query to f ($(island | jq -c .surface), $(launcher | jq -c .query))" eval 'island_is ".surface == \"launcher\"" && launcher_is ".query == \"f\""'
wtype -k Escape
exit "$fails"
}
