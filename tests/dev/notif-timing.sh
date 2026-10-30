#!/usr/bin/env bash
# How long a notification holds the island: its app's timeout, 5 s by default, timed on the shell's own mode clock.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
shows() { island | jq -e --arg s "$1" '.mode == "notification" and (.text | contains($s))' >/dev/null 2>&1; }
# Each held time runs from the state read as it showed to the shell's mode change back to rest.
held_since() { echo $(($(island | jq .since) - $1)); }

notify-send -t 0 -a T sticky
until_ok 2000 shows sticky
sleep 10
check "-t 0 is still on the island after 10 s" shows sticky
timeout 0.5 qs ipc call notifs clear
until_ok 2000 mode_is rest

notify-send -t 2000 -a T quick
until_ok 2000 shows quick
since=$(island | jq .since)
until_ok 4000 mode_is rest
held=$(held_since "$since")
# A QML Timer runs on the animation clock, so it may fire a few frames early.
check "-t 2000 leaves between 1.9 and 2.5 s (${held} ms)" test "$held" -ge 1900 -a "$held" -le 2500

gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify -- T 0 "" default "" '[]' '{}' -1 >/dev/null
until_ok 2000 shows default
since=$(island | jq .since)
until_ok 8000 mode_is rest
held=$(held_since "$since")
check "expire_timeout -1 holds 5 s (${held} ms)" test "$held" -ge 4700 -a "$held" -le 5300

id=$(notify-send -p -a T "copy 10%")
until_ok 2000 shows "copy 10%"
since=$(island | jq .since)
until_ok 4000 eval '(($(now_ms) - since >= 3000))'
notify-send -r "$id" -a T "copy 90%"
until_ok 1000 shows "copy 90%"
until_ok 9000 mode_is rest
held=$(held_since "$since")
check "a replace at 3 s holds it until 8 s (${held} ms)" test "$held" -ge 7700 -a "$held" -le 8500

exit $((fails > 0))
}
