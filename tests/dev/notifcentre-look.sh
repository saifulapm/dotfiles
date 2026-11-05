#!/usr/bin/env bash
# The notification centre draws in the launcher's one design: a tint pill heading, a tinted rounded cursor row, a solid rule and lower-case key chips.
{
source "$(dirname "$0")/lib.sh"

notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
state_is() { notifs | jq -e "$1" >/dev/null; }
# A notification sent just before the centre opens, so its row's age is under a minute; the newest row comes first.
send_fresh() { local n; n=$(notifs | jq .count); notify-send -a mail "fresh $1"; until_ok 2000 state_is ".count == $((n + 1))"; }
one_timer() { shell_status | jq -e '.timers == 1' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_centre() { niri msg action spawn -- dots-call notifs toggle; until_ok 3000 state_is '.open and .settled and .cursorBox != null'; }
close_centre() { niri msg action spawn -- dots-call notifs toggle; until_ok 2000 state_is '.open == false and .drawing == false'; }
# Pixels of geometry $1 within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
# A geometry inside the state's box $1: x offset, y offset, width and height; a negative offset counts from the far edge.
box_geo() {
  notifs | jq -r --arg b "$1" --argjson dx "$2" --argjson dy "$3" --argjson w "$4" --argjson h "$5" \
    '.[$b] | "\((if $dx < 0 then .x + .w + $dx else .x + $dx end) | floor),\((if $dy < 0 then .y + .h + $dy else .y + $dy end) | floor) \($w)x\($h)"'
}

until_ok 5000 shell_status >/dev/null
# An entry from 3 h 1 min ago, read from the history file as the shell restarts; its group sorts last.
old=$(($(now_ms) - 10860000))
printf '{"dnd":false,"history":[{"key":"%s-1","id":1,"app":"old","summary":"old 1","body":"","time":%s,"actions":[]}]}\n' "$old" "$old" >"$DOTS_DEV_DIR/state/dots/notifications.json"
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
until_ok 2000 state_is '.count == 1'
notify-send -a mail "mail 1" "a body line"
notify-send -a chat "chat 1"
until_ok 2000 state_is '.count == 3'

send_fresh fresh
open_centre
check "the fresh row's time column reads now and the oldest 3h ($(notifs | jq -c .ages))" state_is '.ages[0] == "now" and .ages[-1] == "3h"'
check "the heading is the pill reading Notifications ($(notifs | jq -c .heading))" state_is '.heading == "Notifications"'
check "the cursor row's fill is #EEF1FF ($(notifs | jq -c .cursorFill))" state_is '.cursorFill == "#eef1ff"'
tint=$(near "$(box_geo cursorBox 300 2 8 4)" 238 241 255 3)
check "inside the cursor row reads the tint ($tint of 32 px)" test "$tint" -eq 32
corner=$(near "$(box_geo cursorBox 0 0 2 2)" 255 255 255 3)
check "the cursor row's corner reads the card's white, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
check "the legend keys are lower-case ($(notifs | jq -c .legendKeys))" state_is '.legendKeys == ["j/k", "↵", "d", "⇧D", "m", "i", "s", "1-3", "/", "esc"]'
check "the legend reads j/k move first ($(notifs | jq -c .legend))" state_is '.legend | startswith("j/k move  ↵ open  d dismiss  ⇧D clear all")'
check "the rule sits under the heading" state_is '.ruleBox.y > .headingBox.y'
# The fresh notification's 5 s in the island end first; the ages need no timer of their own.
until_ok 7000 one_timer
check "with the centre open status still reports one timer ($(shell_status | jq -c .timers))" one_timer
# wtype -k D sends the keysym without Shift, which Qt reads as d, so the check holds Shift as a person does.
until_ok 2000 state_is .keyboard
wtype -M shift -k d -m shift
until_ok 2000 state_is .hint
check "the empty list's hint names search and esc ($(notifs | jq -c .hintKeys))" state_is '.hint and .hintKeys == ["/", "esc"]'
close_centre

# An app name is whatever the sender says: a long one elides inside the card, a newline stays on one line, and none at all leaves just the count.
notify_as() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "" '[]' '{}' 5000 >/dev/null; }
notify_as "App $(printf 'long%.0s' {1..50})" "long"
notify_as $'two\nlines' "newline"
notify_as "" "no app"
until_ok 2000 state_is '.count == 3'
open_centre
echo "     heads: $(notifs | jq -c '[.heads[] | {text: .text[0:24], elided, lines, right}] + [{cardRight}]')"
check "a long app name elides inside the card" state_is '[.heads[] | select(.text | startswith("App long"))] | length == 1 and (.[0].elided)'
check "no group head runs past the card or onto a second line" state_is '. as $s | all(.heads[]; .right <= $s.cardRight and .lines == 1)'
check "an app sent without a name heads its group with the count alone" state_is 'any(.heads[]; .text == "1")'
close_centre

exit $((fails > 0))
}
