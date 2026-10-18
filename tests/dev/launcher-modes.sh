#!/usr/bin/env bash
# The query prefix picks the launcher's mode: = calculates, > lists commands, w lists windows.
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_space() { niri msg action spawn -- qs ipc call launcher toggle; }
# niri lists the layer Exclusive a moment before its keys arrive, so typing waits until the window has the keyboard.
open_launcher() { mod_space; until_ok 3000 state_is '.open and .query == "" and .keyboard'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
windows_n() { niri msg -j windows | jq length; }

until_ok 5000 shell_status >/dev/null

open_launcher
wtype "= 1440 * 1.25"
until_ok 3000 state_is '.mode == "calculator" and .results == ["1800"]'
check "= 1440 * 1.25 shows the single result 1800" state_is '.mode == "calculator" and .results == ["1800"]'
close_launcher

open_launcher
wtype "= 2 +"
until_ok 3000 state_is '.mode == "calculator" and .query == "= 2 +"'
check "an incomplete expression shows no row" state_is '.mode == "calculator" and .results == []'
close_launcher

open_launcher
wtype "> lo"
until_ok 3000 state_is '.mode == "commands" and .results[0] == "lock"'
check "> lo lists lock first" state_is '.mode == "commands" and .results[0] == "lock"'
close_launcher

niri msg action spawn -- foot
niri msg action spawn -- foot
two_windows() { [ "$(windows_n)" = 2 ]; }
until_ok 8000 two_windows
open_launcher
wtype "w foot"
until_ok 3000 state_is '.mode == "windows" and (.results | length) == 2'
check "w foot lists both windows" state_is '.mode == "windows" and (.results | length) == 2'
first=$(launcher_state | jq -r '.ids[0]')
wtype -k Return
focused_is_first() { [ "$(niri msg -j focused-window | jq .id)" = "$first" ]; }
until_ok 3000 focused_is_first
check "Enter focuses the first row's window" focused_is_first

exit $((fails > 0))
