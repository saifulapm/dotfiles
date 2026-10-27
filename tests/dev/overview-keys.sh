#!/usr/bin/env bash
# While niri's overview is open the shell holds the keyboard, and it lets go once the overview closes.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
no_shell_keyboard() { niri msg -j layers | jq -e 'all(.[]; (.namespace | startswith("dots-") | not) or .keyboard_interactivity == "None")' >/dev/null; }
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }

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
sleep 0.3

niri msg action close-overview
until_ok 2000 surfaces_focus None
check "the closed overview leaves no shell surface holding the keyboard" no_shell_keyboard
until_ok 2000 foot_focused
wtype -k Shift_L
wtype ls
wtype -k Return
typed_now() { [ -s "$typed" ]; }
until_ok 3000 typed_now
check "the foot read ls, without the c typed in the overview ($(cat "$typed" 2>/dev/null))" test "$(cat "$typed" 2>/dev/null)" = ls
check "the overview is closed" overview_is false

exit $((fails > 0))
}
