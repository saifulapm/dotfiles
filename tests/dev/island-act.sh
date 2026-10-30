#!/usr/bin/env bash
# Acting on a notification from the island: Mod+I, then Enter opens it and d or Esc puts it away.
{
source "$(dirname "$0")/lib.sh"
out=$(mktemp)
cleanup() { rm -f "$out"; }

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- dots-call island focus; }
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
in_history() { notifs | jq -e --arg s "$1" 'any(.summaries[]; . == $s)' >/dev/null; }

# -w keeps notify-send waiting, and it prints the action it was told was invoked.
notify-send -u critical -A default=Open -w "deploy done" >"$out" &
until_ok 2000 mode_is notification
mod_i
until_ok 2000 island_focus Exclusive
check "Mod+I gives a notification the keyboard" island_focus Exclusive
wtype -k Return
until_ok 2000 eval 'grep -qx default "$out"'
check "Enter runs the notification's default action" grep -qx default "$out"
until_ok 2000 mode_is rest
check "and the island goes back to the clock" mode_is rest
check "and gives the keyboard back" island_focus None

notify-send -u critical "stop"
until_ok 2000 mode_is notification
mod_i
until_ok 2000 island_focus Exclusive
wtype -k d
until_ok 2000 mode_is rest
check "d puts a critical notification away" mode_is rest
check "and it stays in the history" in_history stop
check "and the keyboard is given back" island_focus None

notify-send -u critical "halt"
until_ok 2000 mode_is notification
mod_i
until_ok 2000 island_focus Exclusive
wtype -k Escape
until_ok 2000 mode_is rest
check "Esc puts it away too" mode_is rest

# Mod+I's focus pauses the hold, so the notification leaves by its app closing it.
id=$(notify-send -p "brief")
until_ok 2000 mode_is notification
mod_i
until_ok 2000 island_focus Exclusive
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null
until_ok 2000 mode_is rest
check "a notification its app closes while focused gives the keyboard back" island_focus None

exit $((fails > 0))
}
