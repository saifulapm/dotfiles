#!/usr/bin/env bash
# What arrives while a surface is open waits behind a 6 px accent dot; after the close it shows one at a time in arrival order, questions first, and a notification whose time ran out goes to the centre's list only (7E95CSV2, 3WG2NHE3).
{
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
summaries() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -c .summaries; }
keyboard_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
sheet_open() {
  niri msg action spawn -- dots-call cheatsheet toggle
  until_ok 3000 island_is '.surface == "cheatsheet" and .animating == false'
  until_ok 2000 keyboard_is Exclusive
  sleep 0.3
}
esc() { wtype -k Escape; }
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 keyboard_is Exclusive; sleep 0.3; }
dismiss() { mod_i; esc; }
ask() { jq -n --arg id "$1" '{self: "macbook", questions: [{id: $id, project: "tambour", machine: "nuc", text: "Ship?", options: ["Yes", "No"], recommend: null, person: true, popup: true}]}' >"$DOTS_HUB_QUESTIONS.tmp" && mv "$DOTS_HUB_QUESTIONS.tmp" "$DOTS_HUB_QUESTIONS"; }
no_questions() { printf '{"self": "macbook", "questions": []}\n' >"$DOTS_HUB_QUESTIONS"; }
# One output pixel as #RRGGBB.
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n' | tr a-f A-F | sed 's/^/#/'; }
player=""
cleanup() {
  [ -z "$player" ] || kill "$player" 2>/dev/null
  rm -rf "$fake"
}

until_ok 3000 island_is '.mode == "rest"'

# 1. A notification waits behind the open sheet, with the dot.
sheet_open
notify-send hi
until_ok 2000 island_is '.waiting == 1'
check "with the cheat sheet open, notify-send hi leaves surface at cheatsheet and waiting at 1" island_is '.surface == "cheatsheet" and .waiting == 1 and .mode == "surface"'
read -r dx dy dc < <(island | jq -r '.dot | "\((.x + .w / 2) | floor) \((.y + .h / 2) | floor) \(.color | ascii_upcase)"')
dot_px=$(px "$dx" "$dy")
check "a pixel of the accent $dc shows on the island at the dot ($dot_px at $dx,$dy)" test "$dot_px" = "$dc"
esc
until_ok 3000 island_is '.mode == "notification"'
check "Esc then shows hi as a card, and waiting reads 0" island_is '.note.summary == "hi" and .waiting == 0'
dismiss
until_ok 3000 island_is '.mode == "rest"'

# 2. A question goes before a notification that came first.
sheet_open
notify-send -t 20000 first
ask Q1
until_ok 2000 island_is '.waiting == 2'
check "a notification then a question while the sheet is open wait as 2" island_is '.waiting == 2 and .surface == "cheatsheet"'
esc
until_ok 3000 island_is '.mode == "question"'
check "after Esc the question shows first" island_is '.mode == "question"'
no_questions
until_ok 3000 island_is '.mode == "notification"'
check "then the notification" island_is '.note.summary == "first"'
dismiss
until_ok 3000 island_is '.mode == "rest"'

# 3. One that ran out while it waited goes to the list without showing.
sheet_open
notify-send -t 1000 gone
until_ok 2000 island_is '.waiting == 1'
sleep 3
esc
saw=no
for _ in $(seq 15); do
  island_is '.mode == "notification"' && saw=yes
  sleep 0.1
done
check "notify-send -t 1000 gone, then Esc 3 s later: no card shows" test "$saw" = no
check "and the notification centre lists gone ($(summaries))" bash -c "timeout 0.5 qs ipc call notifs state | jq -e '.summaries | index(\"gone\") != null' >/dev/null"

# 4. A critical one shows after the close and stays.
sheet_open
notify-send -u critical stay
until_ok 2000 island_is '.waiting == 1'
esc
until_ok 3000 island_is '.mode == "notification"'
check "notify-send -u critical stay shows after Esc" island_is '.note.summary == "stay"'
sleep 6
check "and stays until dismissed" island_is '.mode == "notification" and .note.summary == "stay"'
dismiss
until_ok 3000 island_is '.mode == "rest"'

# 5. Ten show one at a time, in arrival order.
sheet_open
for n in 1 2 3 4 5 6 7 8 9 10; do notify-send -t 0 "n$n"; done
until_ok 3000 island_is '.waiting == 10'
check "ten notifications sent while the sheet is open wait as 10" island_is '.waiting == 10'
esc
seen=()
for n in 1 2 3 4 5 6 7 8 9 10; do
  until_ok 3000 island_is '.mode == "notification" and .animating == false'
  seen+=("$(island | jq -r .note.summary)")
  dismiss
done
check "they show one at a time after Esc, in order (${seen[*]})" test "${seen[*]}" = "n1 n2 n3 n4 n5 n6 n7 n8 n9 n10"
until_ok 3000 island_is '.mode == "rest"'

# 6. A volume key changes the volume and its OSD has run out by the close.
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 3000 island_is '.mode == "rest"'
before=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
sheet_open
niri msg action spawn -- wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
until_ok 2000 bash -c "[ \"\$(wpctl get-volume @DEFAULT_AUDIO_SINK@)\" != '$before' ]"
check "a volume key pressed while the sheet is open changes the volume ($before to $(wpctl get-volume @DEFAULT_AUDIO_SINK@))" test "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" != "$before"
check "and the sheet stays open" island_is '.surface == "cheatsheet"'
sleep 2
esc
saw=no
for _ in $(seq 10); do
  island_is '.mode == "osd"' && saw=yes
  sleep 0.1
done
check "2 s later, after Esc, no OSD draws" test "$saw" = no

# 7. Under Do Not Disturb a plain notification never waits.
timeout 0.5 qs ipc call notifs dnd true >/dev/null
sheet_open
notify-send quiet
sleep 1
check "with Do Not Disturb on, a notification sent while the sheet is open leaves waiting at 0" island_is '.waiting == 0'
esc
saw=no
for _ in $(seq 15); do
  island_is '.mode == "notification"' && saw=yes
  sleep 0.1
done
check "and never shows" test "$saw" = no
timeout 0.5 qs ipc call notifs dnd false >/dev/null

# 8. Do Not Disturb turned on while one waits keeps it off the island.
sheet_open
notify-send -t 0 late
until_ok 2000 island_is '.waiting == 1'
timeout 0.5 qs ipc call notifs dnd true >/dev/null
esc
saw=no
for _ in $(seq 15); do
  island_is '.mode == "notification"' && saw=yes
  sleep 0.1
done
check "a notification that waited while Do Not Disturb went on never shows" test "$saw" = no
timeout 0.5 qs ipc call notifs dnd false >/dev/null

# 9. A replace of the one showing, sent while the sheet is open, updates it and waits as no copy.
id=$(notify-send -p -t 0 "step 1")
until_ok 3000 island_is '.mode == "notification" and .note.summary == "step 1" and .animating == false'
sheet_open
notify-send -r "$id" -t 0 "step 2"
sleep 0.5
check "a replace of the notification showing waits as nothing ($(island | jq .waiting))" island_is '.waiting == 0'
esc
until_ok 3000 island_is '.mode == "notification" and .note.summary == "step 2"'
check "and after Esc it shows once, as its new text" island_is '.note.summary == "step 2"'
dismiss
saw=no
for _ in $(seq 10); do
  island_is '.mode == "notification"' && saw=yes
  sleep 0.1
done
check "and no second copy follows it" test "$saw" = no

# 10. A track starting while the sheet is open lights the dot as one, then plays after Esc.
sheet_open
"$repo/bin/dev-fake-mpris" Track Artist 9>&- &
player=$!
until_ok 3000 island_is '.waiting == 1'
check "a track starting while the sheet is open lights the dot ($(island | jq -c '{waiting, dot}'))" island_is '.waiting == 1 and .dot != null and .surface == "cheatsheet"'
esc
until_ok 3000 island_is '.mode == "playing"'
check "and after Esc the island shows it playing, waiting 0" island_is '.mode == "playing" and .waiting == 0'
kill "$player" 2>/dev/null
exit "$fails"
}
