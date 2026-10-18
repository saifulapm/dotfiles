#!/usr/bin/env bash
# The margins and the island, from niri's event stream and the shell's one minute tick.
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }

niri msg action spawn -- foot
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused
check "foot is focused" foot_focused
# Between the margin rule at y=40 and the window top at y=56 there is only paper.
strip=$(grim -s 1 -t ppm -g "40,44 10x10" - | mean_rgb)
echo "     margin strip with foot open: $strip"
check "foot opens below the margins" test "$strip" = "241 233 216"
# niri animates a window open, so the frame is polled until the window has settled.
edge_is_ink() { edge=$(grim -s 1 -t ppm -g "32,300 1x10" - | mean_rgb); [ "$edge" = "28 25 21" ]; }
until_ok 1000 edge_is_ink
check "niri draws foot's ink frame at x=32 ($edge)" edge_is_ink

# foot's shell retitles the window once it starts, so the title is read again on every poll.
left_is_foot() {
  title=$(niri msg -j focused-window | jq -r .title)
  margins | jq -e --arg t "$title" '.left.text == "01 · foot — " + $t' >/dev/null 2>&1
}
until_ok 1000 left_is_foot
echo "     margins: $(margins)"
check "the top-left reads 01 · foot — <foot's title>" left_is_foot

niri msg action focus-workspace 2
start=$(now_ms)
reads_02() { margins | jq -e '.left.text == "02"' >/dev/null 2>&1; }
# No sleep between reads, so the poll adds no delay of its own.
until reads_02; do (($(now_ms) - start < 2000)) || break; done
elapsed=$(($(now_ms) - start))
check "the top-left reads 02 ${elapsed} ms after focus-workspace 2" test "$elapsed" -le 100

island_is_now() {
  local text now
  text=$(island | jq -r .text 2>/dev/null)
  now=$(date +%H:%M)
  echo "     island: $text, date: $now"
  [ "$text" = "$now" ]
}
# The minute can roll over between the two reads, so one mismatch earns one re-read.
island_now_or_next() { island_is_now || island_is_now; }
check "the island shows date +%H:%M" island_now_or_next

status=$(shell_status)
echo "     status: $status"
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "status reports one running timer" one_timer

layers=$(niri msg -j layers)
on_top() { jq -e --arg ns "$1" 'any(.[]; .namespace == $ns and .layer == "Top")' <<<"$layers" >/dev/null; }
check "dots-margins is on the Top layer" on_top dots-margins
check "dots-island is on the Top layer" on_top dots-island

exit $((fails > 0))
