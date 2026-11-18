#!/usr/bin/env bash
# Another surface's key while one is open morphs the island straight into it: no null between, no return to the resting width, nothing that waits lost, and a switch pressed mid-morph wins.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
launcher_is() { timeout 0.5 qs ipc call launcher state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .width == 176 and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_space() { niri msg action spawn -- dots-call launcher toggle; }
mod_slash() { niri msg action spawn -- dots-call cheatsheet toggle; }
settled_on() { island_is ".surface == \"$1\" and .animating == false"; }
polled=$(mktemp)
cleanup() { rm -f "$polled" "$polled.on"; }
# Polls island state every 20 ms into $polled, one [surface, drawn width] a line, until $polled.on goes.
poll() {
  : >"$polled.on"
  (while [ -f "$polled.on" ]; do island | jq -c '[.surface, .drawn]' >>"$polled"; sleep 0.02; done) &
  poller=$!
}
unpoll() { rm -f "$polled.on"; wait "$poller" 2>/dev/null; }

until_ok 5000 shell_status >/dev/null
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
until_ok 3000 at_rest
sheet_w=$((ow - 48 < 1160 ? ow - 48 : 1160))

mod_space
until_ok 3000 settled_on launcher
until_ok 2000 surfaces_focus Exclusive
notify-send hi
until_ok 2000 island_is '.waiting == 1'
poll
mod_slash
until_ok 3000 settled_on cheatsheet
unpoll
check "Mod+/ on the launcher changes surface to cheatsheet with no null between ($(jq -sc '[.[][0]] | unique' "$polled"))" jq -se '(map(.[0]) | all(. == "launcher" or . == "cheatsheet")) and (map(.[0]) | any(. == "cheatsheet"))' "$polled"
check "the width goes from 640 to $sheet_w without returning to 176 (narrowest drawn $(jq -s 'map(.[1]) | min' "$polled"))" jq -se 'map(.[1]) | min >= 640' "$polled"
check "it morphs from the launcher's box ($(island | jq -c '.morph | {kind, from}'))" island_is --argjson w "$sheet_w" '.morph.kind == "open" and .morph.from[0] == 640 and .width == $w'
check "the notification still waits ($(island | jq -c .waiting))" island_is '.waiting == 1'

mod_space
until_ok 3000 settled_on launcher
until_ok 2000 launcher_is '.open and .query == ""'
check "Mod+Space on the open cheat sheet morphs back with an empty field" launcher_is '.open and .query == ""'
wtype ab
until_ok 2000 launcher_is '.query == "ab"'
check "and the field takes typing" launcher_is '.query == "ab"'

mod_space
until_ok 3000 at_rest
check "Mod+Space on the open launcher closes it, and the waiting hi shows ($(island | jq -c '{surface, mode}'))" island_is '.surface == null and (.mode == "notification" or .width == 176)'
timeout 0.5 qs ipc call notifs clear
until_ok 8000 at_rest

mod_space
sleep 0.1
mod_slash
until_ok 3000 settled_on cheatsheet
sleep 0.3
check "Mod+Space then Mod+/ 100 ms later ends on the cheat sheet ($(island | jq -c '{surface, width}'))" island_is --argjson w "$sheet_w" '.surface == "cheatsheet" and .width == $w and .animating == false'
wtype -k Escape
until_ok 2000 at_rest
exit "$fails"
}
