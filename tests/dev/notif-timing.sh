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

# The pointer on the island's box, or Mod+I's focus, pauses the hold; let go, it resumes what it had left, at least 1.5 s.
dots_pointer_build || exit 1
box=$(niri msg -j outputs | jq -r '[.[] | .logical] | (map(.x) | min) as $x | (map(.y) | min) as $y | "\($x),\($y),\((map(.x + .width) | max) - $x),\((map(.y + .height) | max) - $y)"')
dp() { "$DOTS_DEV_DIR/dots-pointer/dots-pointer" "$box" "$@"; }
away() { dp move 40 1200; }
onto() { dp move $(island | jq -r '.note.summaryBox | "\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"'); }
since_more() { (($(now_ms) - $1 >= $2)); }
away

notify-send -a T hover
until_ok 2000 shows hover
onto
sleep 8
check "a 5 s notification with the pointer on the island for 8 s is still shown" shows hover
let_go=$(now_ms)
away
until_ok 6000 mode_is rest
held=$(held_since "$let_go")
check "let go, it holds the time it had left (${held} ms)" test "$held" -ge 4000 -a "$held" -le 5100

notify-send -a T later
until_ok 2000 shows later
since=$(island | jq .since)
until_ok 4000 since_more "$since" 3000
onto
until_ok 2000 since_more "$since" 4000
let_go=$(now_ms)
away
until_ok 4000 mode_is rest
held=$(held_since "$let_go")
check "the pointer on it from 3 s to 4 s in: it leaves 1.5 to 2.5 s after (${held} ms)" test "$held" -ge 1400 -a "$held" -le 2500

notify-send -a T last
until_ok 2000 shows last
since=$(island | jq .since)
until_ok 6000 since_more "$since" 4500
onto
until_ok 2000 since_more "$since" 5500
check "the pointer on it as its 5 s run out keeps it" shows last
let_go=$(now_ms)
away
until_ok 4000 mode_is rest
held=$(held_since "$let_go")
check "with under 1.5 s left it still gets 1.5 s (${held} ms)" test "$held" -ge 1400 -a "$held" -le 2000

notify-send -a T focus
until_ok 2000 shows focus
niri msg action spawn -- dots-call island focus
sleep 8
check "Mod+I's focus held 8 s keeps it shown" shows focus
wtype -k d
until_ok 2000 mode_is rest
check "at rest the shell runs one timer" eval 'shell_status | jq -e ".timers == 1" >/dev/null'

exit $((fails > 0))
}
