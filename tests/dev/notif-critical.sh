#!/usr/bin/env bash
# A critical notification with no timeout of its own stays on the island until dismissed, Do Not Disturb or not, and a restart leaves it in the history only.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
shows() { island | jq -e --arg s "$1" '.mode == "notification" and (.text | contains($s))' >/dev/null 2>&1; }
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
in_history() { notifs | jq -e --arg s "$1" 'any(.summaries[]; . == $s)' >/dev/null; }
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns Mod+I's command through niri.
mod_i_d() {
  niri msg action spawn -- dots-call island focus
  until_ok 2000 island_focus Exclusive
  wtype -k d
}
dnd() { timeout 0.5 qs ipc call notifs dnd "$1" >/dev/null; }

notify-send -u critical -a Test "Disk full"
until_ok 2000 shows "Disk full"
sleep 10
check "a critical is still on the island after 10 s" shows "Disk full"
dnd true
sleep 0.5
check "turning Do Not Disturb on while it shows keeps it" shows "Disk full"
mod_i_d
until_ok 2000 mode_is rest
check "Mod+I, d puts it away and the island rests" mode_is rest
check "and Mod+A still lists it" in_history "Disk full"

notify-send -u critical -a Test "Disk low"
until_ok 2000 shows "Disk low"
sleep 10
check "with Do Not Disturb on a critical shows and is still there after 10 s" shows "Disk low"
mod_i_d
until_ok 2000 mode_is rest

notify-send -u critical -t 3000 -a Test "brief"
until_ok 2000 shows brief
since=$(island | jq .since)
until_ok 5000 mode_is rest
held=$(($(island | jq .since) - since))
check "a critical with -t 3000 leaves after 3 s (${held} ms)" test "$held" -ge 2850 -a "$held" -le 3500

notify-send -u critical -a Test "Disk gone"
until_ok 2000 shows "Disk gone"
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
until_ok 3000 mode_is rest
check "after a shell restart the island rests" mode_is rest
check "and the critical is in the history" in_history "Disk gone"

exit $((fails > 0))
}
