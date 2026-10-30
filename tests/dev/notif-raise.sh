#!/usr/bin/env bash
# After a notification's default action or a chip runs, niri focuses the app's most recently focused window.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
shows() { island | jq -e --arg s "$1" '.mode == "notification" and (.note.summary | ascii_downcase) == $s' >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() {
  niri msg action spawn -- dots-call island focus
  until_ok 2000 island_focus Exclusive
}
focused() { niri msg -j focused-window | jq -r '"\(.app_id) \(.title)"'; }
focused_is() { [ "$(focused)" = "$1" ]; }
id_of() { niri msg -j windows | jq -r --arg t "$1" '.[] | select(.title == $t) | .id'; }
focus() { niri msg action focus-window --id "$(id_of "$1")"; until_ok 2000 focused_is "$2 $1"; }
open_window() {
  niri msg action spawn -- foot -c /dev/null -a "$1" -T "$2" sleep 600
  until_ok 5000 focused_is "$1 $2"
}
# notify-send -A waits for the action; the key is pressed on the focused island.
act() {
  local summary=$1 key=$2
  shift 2
  notify-send "$@" "$summary" >/dev/null &
  until_ok 2000 shows "$summary"
  mod_i
  wtype -k "$key"
  until_ok 2000 mode_is rest
}

open_window foot first
open_window other else
act hi Return -a foot -h string:desktop-entry:foot -A default=Open
check "Enter on a foot notification focuses the foot window" until_ok 2000 focused_is "foot first"

# niri stamps a window's focus only once it has held it for about a second, as a person working in it does.
open_window foot second
focus first foot
sleep 1.5
focus else other
act two Return -a foot -A default=Open
check "with two foot windows, the one focused last takes focus" until_ok 2000 focused_is "foot first"

focus second foot
sleep 1.5
focus else other
act chip 1 -a Foot -A yes=Yes
check "a chip on an app Foot notification focuses the foot window focused last" until_ok 2000 focused_is "foot second"

focus else other
act none Return -a nomatch -A default=Open
sleep 1
check "with no matching window, focus does not change ($(focused))" focused_is "other else"

exit $((fails > 0))
}
