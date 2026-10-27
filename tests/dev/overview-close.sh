#!/usr/bin/env bash
# Esc and Enter in niri's open overview close it: Esc keeps the focus where it was, Enter keeps the window the overview shows focused.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }
focused_id() { niri msg -j windows | jq -r 'first(.[] | select(.is_focused)).id // empty'; }
windows_are() { test "$(niri msg -j windows | jq length)" = "$1"; }
open_overview() {
  niri msg action open-overview
  until_ok 2000 surfaces_focus Exclusive
  # wtype's first key into a newly focused surface can take the old keymap, so a Shift goes first.
  wtype -k Shift_L
}

niri msg action spawn -- foot -c /dev/null
until_ok 5000 windows_are 1
niri msg action spawn -- foot -c /dev/null
until_ok 5000 windows_are 2
first=$(niri msg -j windows | jq -r 'min_by(.id).id')
second=$(niri msg -j windows | jq -r 'max_by(.id).id')
second_focused() { test "$(focused_id)" = "$second"; }
until_ok 3000 second_focused
check "the second foot, in the second column, is focused" second_focused

open_overview
wtype -k Escape
until_ok 2000 overview_is false
check "Esc closes the overview" overview_is false
check "and the focus stays on the second foot ($(focused_id))" second_focused

open_overview
niri msg action focus-column-left
first_focused() { test "$(focused_id)" = "$first"; }
wtype -k Return
until_ok 2000 overview_is false
check "Enter after a move to the first column closes the overview" overview_is false
until_ok 1000 first_focused
check "and the first foot is focused ($(focused_id), first is $first)" first_focused
check "the shell let go of the keyboard" surfaces_focus None

exit $((fails > 0))
}
