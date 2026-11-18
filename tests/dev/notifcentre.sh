#!/usr/bin/env bash
# Mod+A opens the notification centre: grouped by app, d dismisses, D clears all, Esc gives the keyboard back.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
state_is() { notifs | jq -e "$1" >/dev/null; }
island_is() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e --arg m "$1" '.mode == $m' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_a() { niri msg action spawn -- dots-call notifs toggle; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
centre_open() { state_is '.open and .keyboard and .settled' && focus_is Exclusive; }
centre_closed() { state_is '.open == false' && focus_is None; }

notify-send -a mail "mail 1"
notify-send -a chat "chat 1"
notify-send -a mail "mail 2"
until_ok 2000 state_is '.count == 3'

mod_a
until_ok 3000 centre_open
check "Mod+A shows the centre with exclusive keyboard" centre_open
state=$(notifs)
echo "     notifs: $state"
holds() { jq -e "$1" <<<"$state" >/dev/null; }
check "the centre shows 2 groups, newest first" holds '.groups == [{app: "mail", entries: ["mail 2", "mail 1"]}, {app: "chat", entries: ["chat 1"]}]'
check "status lists notifs in loaded" bash -c 'timeout 0.5 qs ipc call shell status | jq -e "any(.loaded[]; . == \"notifs\")" >/dev/null'

wtype -k d
until_ok 2000 state_is '.count == 2'
check "d dismisses the selected entry" state_is '.count == 2 and .summaries == ["chat 1", "mail 1"]'

# wtype -k D sends the keysym without Shift, which Qt reads as d, so the check holds Shift as a person does.
wtype -M shift -k d -m shift
until_ok 2000 state_is '.count == 0'
check "D clears the history and draws Nothing new" state_is '.count == 0 and .groups == [] and .empty'

wtype -k Escape
until_ok 2000 centre_closed
check "Esc closes the centre and releases the keyboard" centre_closed

notify-send -u critical stop
until_ok 2000 island_is notification
mod_a
until_ok 3000 centre_open
wtype -k d
until_ok 2000 state_is '.count == 0'
check "the dismiss took it from the history" state_is '.count == 0'
# The centre is the island now, so the critical's leaving shows once the centre closes.
wtype -k Escape
until_ok 2000 centre_closed
until_ok 2000 island_is rest
check "a critical notification dismissed with d does not come back to the island" island_is rest
check "at rest the shell runs one timer" bash -c 'timeout 0.5 qs ipc call shell status | jq -e ".timers == 1" >/dev/null'

exit $((fails > 0))
}
