#!/usr/bin/env bash
# Esc in a launcher opened from niri's overview returns to the overview; launching an app or picking a window closes both.
{
source "$(dirname "$0")/lib.sh"

surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
overview_is() { niri msg -j overview-state | jq -e ".is_open == $1" >/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
query() { launcher_state | jq -c .query; }
windows_are() { test "$(niri msg -j windows | jq length)" = "$1"; }
focused_title() { niri msg -j windows | jq -r 'first(.[] | select(.is_focused)).title // empty'; }
open_overview() {
  niri msg action open-overview
  until_ok 2000 surfaces_focus Exclusive
  # wtype's first key into a newly focused surface can take the old keymap, so a Shift goes first.
  wtype -k Shift_L
}

niri msg action spawn -- foot -c /dev/null -T zebra
until_ok 5000 windows_are 1
niri msg action spawn -- foot -c /dev/null -T other
until_ok 5000 windows_are 2
other_focused() { test "$(focused_title)" = other; }
until_ok 3000 other_focused
check "the foot titled other is focused" other_focused

open_overview
wtype f
until_ok 2000 launcher_is '.open and .query == "f"'
wtype -k Escape
until_ok 2000 launcher_is '.open == false'
check "Esc closes the launcher" launcher_is '.open == false'
sleep 0.3
check "and leaves the overview open" overview_is true
wtype x
until_ok 2000 launcher_is '.open and .query == "x"'
check "then x opens the launcher again reading x ($(query))" launcher_is '.open and .query == "x"'
wtype -k Escape
until_ok 2000 launcher_is '.open == false'

wtype foot
until_ok 2000 launcher_is '.open and .query == "foot" and .results[0] == "Foot"'
wtype -k Return
until_ok 5000 windows_are 3
t0=$(now_ms)
until_ok 2000 overview_is false
ms=$(($(now_ms) - t0))
check "Enter on Foot opens a third window" windows_are 3
check "and the overview closes ${ms} ms after it appears" test "$ms" -le 500
check "the shell let go of the keyboard" surfaces_focus None

open_overview
wtype "w zebra"
until_ok 2000 launcher_is '.open and .mode == "windows" and .results[0] == "zebra"'
check "w zebra lists the zebra window first ($(launcher_state | jq -c .results))" launcher_is '.results[0] == "zebra"'
wtype -k Return
until_ok 2000 overview_is false
check "Enter on it closes the overview" overview_is false
zebra_focused() { test "$(focused_title)" = zebra; }
until_ok 2000 zebra_focused
check "and focuses zebra ($(focused_title))" zebra_focused

open_overview
wtype ab
until_ok 2000 launcher_is '.open and .query == "ab"'
niri msg action toggle-overview
until_ok 2000 overview_is false
until_ok 2000 launcher_is '.open == false'
check "the overview closed another way closes the launcher it opened" launcher_is '.open == false'
until_ok 2000 surfaces_focus None
check "and the shell lets go of the keyboard" surfaces_focus None

open_overview
niri msg action spawn -- dots-call launcher toggle
until_ok 2000 launcher_is '.open and .query == ""'
niri msg action toggle-overview
until_ok 2000 overview_is false
sleep 0.3
check "a launcher Mod+Space opened stays open when the overview closes" launcher_is '.open'

exit $((fails > 0))
}
