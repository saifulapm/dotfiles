#!/usr/bin/env bash
# While niri's overview is open the shell holds the keyboard and a printable key opens the launcher with it typed; the shell lets go once the overview closes.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
no_shell_keyboard() { niri msg -j layers | jq -e 'all(.[]; (.namespace | startswith("dots-") | not) or .keyboard_interactivity == "None")' >/dev/null; }
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
query() { launcher_state | jq -c .query; }
close_launcher() {
  timeout 0.5 qs ipc call launcher close
  until_ok 2000 launcher_is '.open == false'
}

typed=$(mktemp -u)
cleanup() { rm -f "$typed"; }
niri msg action spawn -- foot -c /dev/null -e sh -c "read x; echo \"\$x\" > $typed"
foot_focused() { niri msg -j focused-window | jq -e '.app_id == "foot"' >/dev/null; }
until_ok 5000 foot_focused
check "a foot is focused" foot_focused

niri msg action open-overview
until_ok 2000 surfaces_focus Exclusive
check "the open overview gives the shell's surfaces the keyboard" surfaces_focus Exclusive
# wtype's first key into a newly focused surface can take the old keymap, so a Shift goes first.
wtype -k Shift_L
wtype c
until_ok 2000 launcher_is '.open and .query == "c"'
check "c in the overview opens the launcher reading c ($(query))" launcher_is '.open and .mode == "apps" and .query == "c"'
close_launcher

wtype chr
until_ok 2000 launcher_is '.open and .query == "chr"'
check "chr in one call reads chr, no key lost ($(query))" launcher_is '.open and .query == "chr"'
close_launcher

# wtype's -M shift capitalises nothing in any Qt field, so the check types A, which Qt reads as Shift+a's text; the live walk presses a real Shift+a.
wtype A
until_ok 2000 launcher_is '.open and .query == "A"'
check "A reads A ($(query))" launcher_is '.open and .query == "A"'
close_launcher

wtype -M ctrl c -m ctrl
wtype -M alt x -m alt
wtype -M logo o -m logo
sleep 0.5
check "Ctrl+c, Alt+x and Mod+o leave the launcher closed" launcher_is '.open == false'
check "and the overview open" overview_is true

niri msg action close-overview
until_ok 2000 surfaces_focus None
check "the closed overview leaves no shell surface holding the keyboard" no_shell_keyboard
until_ok 2000 foot_focused
wtype -k Shift_L
wtype ls
wtype -k Return
typed_now() { [ -s "$typed" ]; }
until_ok 3000 typed_now
check "the foot read ls, and nothing typed in the overview ($(cat "$typed" 2>/dev/null))" test "$(cat "$typed" 2>/dev/null)" = ls
check "the overview is closed" overview_is false

exit $((fails > 0))
}
