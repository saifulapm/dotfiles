#!/usr/bin/env bash
# Mod+I opens the calendar and Mod+I again closes it; the pointer resting on the island opens it without the keyboard, and leaving closes it.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
keyboard_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- dots-call island focus; }
typed=$DOTS_DEV_DIR/typed

until_ok 3000 island_is '.mode == "rest" and .animating == false'
mod_i
until_ok 3000 island_is '.mode == "calendar" and .focused'
check "Mod+I opens the calendar with the keyboard" keyboard_is Exclusive
mod_i
until_ok 3000 island_is '.mode == "rest"'
check "a second Mod+I closes it" island_is '.mode == "rest" and .focused == false'
until_ok 2000 keyboard_is None
check "and gives the keyboard back" keyboard_is None

notify-send -t 0 "Stays"
until_ok 3000 island_is '.mode == "notification" and .animating == false'
mod_i
until_ok 2000 island_is '.focused'
mod_i
until_ok 2000 island_is '.focused == false'
check "a second Mod+I on a notification unfocuses it and leaves it shown" island_is '.mode == "notification" and .focused == false'
mod_i
until_ok 2000 island_is '.focused'
wtype -k Escape
until_ok 3000 island_is '.mode == "rest" and .animating == false'

# A foot that keeps what is typed, so a key typed while the calendar is open by hover is seen to reach it.
niri msg action spawn -- foot -c /dev/null sh -c "cat > '$typed'"
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
mid=$((ow / 2))
point move 200 900
point move "$mid" 17
point move 200 900
sleep 0.4
check "the pointer crossing the island without resting opens nothing" island_is '.mode == "rest"'
point move "$mid" 17
until_ok 2000 island_is '.mode == "calendar"'
check "the pointer resting on the island opens the calendar" island_is '.mode == "calendar" and .focused == false'
check "without taking the keyboard" keyboard_is None
wtype x
wtype -k Return
until_ok 2000 grep -q x "$typed"
check "so a key typed then reaches the window" grep -q x "$typed"
point move 200 900
until_ok 2000 island_is '.mode == "rest"'
check "and the pointer leaving closes it" island_is '.mode == "rest"'

point move "$mid" 17
until_ok 2000 island_is '.mode == "calendar" and .animating == false'
point click "$mid" 60
until_ok 2000 island_is '.focused'
check "a click in the calendar opened by hover gives it the keyboard" keyboard_is Exclusive
point move 200 900
sleep 0.6
check "and then leaving does not close it" island_is '.mode == "calendar" and .focused'
wtype -k Escape
until_ok 3000 island_is '.mode == "rest"'
exit "$fails"
}
