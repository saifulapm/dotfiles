#!/usr/bin/env bash
# Over a fullscreen window the island hides what is passive, a playing track, the mic and a notification, and shows every question; a notification waits, so a critical one shows once the window leaves fullscreen (4AEWRR0H).
{
export DOTS_DEV_WIREPLUMBER=1
fake=$(mktemp -d)
calls=$fake/calls
cat >"$fake/mem" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$calls"
EOF
chmod +x "$fake/mem"
PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
keyboard_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 keyboard_is Exclusive; sleep 0.3; }
summaries() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -c .summaries; }
called() { grep -qxF -- "$1" "$calls" 2>/dev/null; }
# One output pixel at the output's middle column, $1 px down, as #RRGGBB.
mid_px() { grim -g "$(($(niri msg -j outputs | jq '[.[]][0].logical.width') / 2)),$1 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n' | tr a-f A-F | sed 's/^/#/'; }
recs=()
cleanup() {
  kill "$player" "${recs[@]}" 2>/dev/null
  rm -rf "$fake"
}

until_ok 3000 island_is '.mode == "rest"'
# A foot with nothing in it, so its top rows are its background.
niri msg action spawn -- foot -c /dev/null sh -c 'sleep 600'
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
niri msg action fullscreen-window
until_ok 3000 island_is '.shown == false'
"$repo/bin/dev-fake-mpris" Track Artist 9>&- &
player=$!
pw-record -P '{ application.name = "Rec" }' --raw - >/dev/null 2>&1 9>&- &
recs+=($!)
notify-send hi
sleep 1.5
check "with a fullscreen window, a playing track, a mic in use and notify-send hi draw nothing ($(island | jq -c '{shown, mode}'))" island_is '.shown == false'
check "the output's top row is the window's own pixels ($(mid_px 0), the foot's $(mid_px 300))" test "$(mid_px 0)" = "$(mid_px 300)"
until_ok 6000 bash -c "timeout 0.5 qs ipc call notifs state | jq -e '.summaries | index(\"hi\") != null' >/dev/null"
check "the notification sent while fullscreen is in the notification centre's list ($(summaries))" bash -c "timeout 0.5 qs ipc call notifs state | jq -e '.summaries | index(\"hi\") != null' >/dev/null"
kill "$player" "${recs[@]}" 2>/dev/null

jq -n '{self: "macbook", questions: [{id: "Q1", project: "tambour", machine: "nuc", text: "Ship?", options: ["Yes", "No"], recommend: null, person: true, popup: true}]}' >"$DOTS_HUB_QUESTIONS"
until_ok 3000 island_is '.shown and .mode == "question" and .animating == false'
check "an agent question draws its card over the fullscreen window" island_is '.shown and .mode == "question"'
mod_i
wtype 1
check "and Mod+I then 1 answers it" until_ok 2000 called "answer --by popup -- Q1 Yes"
printf '{"self": "macbook", "questions": []}\n' >"$DOTS_HUB_QUESTIONS"
until_ok 3000 island_is '.shown == false'

# hi's 5 s run out first, so the critical is the only one left waiting.
sleep 4
notify-send -u critical now
saw=no
for _ in $(seq 15); do
  island_is '.shown' && saw=yes
  sleep 0.1
done
check "notify-send -u critical now over a fullscreen window draws nothing" test "$saw" = no
niri msg action fullscreen-window
until_ok 3000 island_is '.shown and .mode == "notification"'
check "and shows once the window leaves fullscreen" island_is '.mode == "notification" and .note.summary == "now"'
exit "$fails"
}
