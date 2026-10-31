#!/usr/bin/env bash
# A YouTube download takes the island's slot with its title, place in a Playlist, percent and a bar, in each theme; a failure holds 5 s over it, and a send outranks it.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$@" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
no_transition() { shell_status | jq -e '.transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; until_ok 2000 no_transition; sleep 0.3; }
settled() { until_ok 3000 state_is "$1 and .animating == false"; sleep 0.1; }
# The island's box: centred on the output, 10 px from the top.
box() { niri msg -j outputs | jq -r --argjson w "$(island | jq .drawn)" --argjson h "$(island | jq .height)" 'first(.[]).logical | "\(((.width - $w) / 2 + .x) | floor),\(.y + 10) \($w | floor)x\($h | floor)"'; }
# Pixels of the box within 12 of r g b.
near() {
  grim -s 1 -t ppm -g "$(box)" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= 12 && Math.abs(px[i * 3 + 1] - g) <= 12 && Math.abs(px[i * 3 + 2] - bl) <= 12) n++;
    console.log(n);
  ' "$@"
}
rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }

until_ok 5000 shell_status >/dev/null
check "at rest the island is the clock" state_is '.mode == "rest" and .downloading == null'
check "a percent before any start is dropped" bash -c 'dots-call downloading progress 30 && sleep 0.3 && ! timeout 0.5 qs ipc call island state | jq -e ".mode == \"downloading\"" >/dev/null'
dots-call downloading start 3 18 Focus Feather audio
dots-call downloading progress 37

for theme in paper artboard blueprint; do
  in_theme "$theme"
  settled '.mode == "downloading"'
  echo "     $theme: $(island | jq -c '{text, width, drawn, downloading}')"
  case $theme in
    paper) width=480 pad=16 fill='#C8381E' head='.downloading.head == []' ;;
    artboard) width=440 pad=16 fill='#6C83FF' head='.downloading.head == ["YouTube", "~/Music/YouTube"]' ;;
    blueprint) width=420 pad=18 fill='#7FE3F0' head='.downloading.head[0] == "[ YOUTUBE ]" and (.downloading.head[1] | test("[0-9]:[0-9]{2}"))' ;;
  esac
  check "$theme: island state reports mode downloading and the line" state_is '.mode == "downloading" and .text == "↓ Focus 3 / 18 · Feather · 37%"'
  check "$theme: the slot draws the line on one line at its board's $width px, the percent at the right edge" state_is ".downloading.line == \"↓ Focus 3 / 18 · Feather · 37%\" and .drawn == $width and .downloading.lines == 1 and (.downloading.right - (.drawn - $pad) | fabs) <= 1 and .downloading.failed == false"
  check "$theme: the head reads as its board draws it" state_is "$head"
  check "$theme: the bar is filled to 37% of its width" state_is '(.downloading.barWidth | type == "number") and .downloading.barFill >= (.downloading.barWidth * 0.35) and .downloading.barFill <= (.downloading.barWidth * 0.39)'
  area=$(island | jq '(.downloading.barFill * .downloading.barHeight * 0.8) | floor')
  check "$theme: the bar's fill colour is drawn over its area ($area px)" test "$(near $(rgb "$fill"))" -ge "$area"
done

in_theme paper
dots-call downloading progress 80
check "progress moves the drawn percent and the fill" until_ok 3000 state_is '.downloading.line == "↓ Focus 3 / 18 · Feather · 80%" and .downloading.barFill >= (.downloading.barWidth * 0.78) and .downloading.barFill <= (.downloading.barWidth * 0.82)'
notify-send -a Test "over the download" "a"
check "a notification shows over the download" until_ok 3000 state_is '.mode == "notification"'
check "and the download comes back once it has gone" until_ok 8000 state_is '.mode == "downloading" and .downloading.line == "↓ Focus 3 / 18 · Feather · 80%"'
dots-call sending start 1 nuc
check "a send outranks the download" until_ok 3000 state_is '.mode == "sending"'
dots-call sending done
check "and the download comes back when the send is done" until_ok 3000 state_is '.mode == "downloading"'
dots-call downloading done
check "done brings the clock back" until_ok 3000 state_is '.mode == "rest" and .downloading == null'

# A failure holds 5 s over a start that arrives meanwhile, then the download underneath shows.
t0=$(now_ms)
dots-call downloading failed Feather "HTTP 403"
dots-call downloading start 4 18 Focus Next audio
settled '.mode == "downloading"'
since=$(island | jq .since)
check "a failure is drawn as it is told, with no bar" state_is '.downloading.failed and .downloading.line == "↓ failed · Feather · HTTP 403" and .downloading.barHeight == 0'
sleep $(awk -v t0="$t0" -v now="$(now_ms)" 'BEGIN { s = 4 - (now - t0) / 1000; print (s > 0 ? s : 0) }')
check "and still at 4 s, in the same mode it began" state_is --argjson s "$since" '.downloading.line == "↓ failed · Feather · HTTP 403" and .since == $s'
check "at about 5 s the download underneath shows" until_ok 3000 state_is '.downloading.line == "↓ Focus 4 / 18 · Next · 0%"'
took=$(($(now_ms) - t0))
check "the hold lasted about 5 s (took $took ms)" test "$took" -ge 4800 -a "$took" -le 6500
dots-call downloading done

# done does not cut a held failure short.
t0=$(now_ms)
dots-call downloading failed X y
dots-call downloading done
sleep 3.5
check "a failure survives done while it is held" state_is '.mode == "downloading" and .downloading.failed'
check "and the island returns to rest after its 5 s" until_ok 3000 state_is '.mode == "rest" and .downloading == null'
took=$(($(now_ms) - t0))
check "the hold lasted about 5 s (took $took ms)" test "$took" -ge 4800 -a "$took" -le 6500

# Artboard draws the failure as a chip, Blueprint frames it in the amber.
in_theme artboard
dots-call downloading failed Feather "HTTP 403"
settled '.mode == "downloading"'
check "artboard: the failure is a chip then the rest" state_is '.downloading.chip == "↓ failed" and .downloading.line == "↓ failed · Feather · HTTP 403"'
in_theme blueprint
dots-call downloading failed Feather "HTTP 403"
settled '.mode == "downloading"'
check "blueprint: the failure frames in the amber" state_is '.downloading.failed and (.downloading.frame | ascii_downcase | startswith("#ffb547"))'
until_ok 8000 state_is '.mode == "rest"'
in_theme paper

# A single download reads without a place, and a forged or long title elides before the percent.
dots-call downloading start 1 1 "" Feather audio
settled '.mode == "downloading"'
check "a single download reads its title and 0%" state_is '.text == "↓ Feather · 0%" and .downloading.line == "↓ Feather · 0%"'
dots-call downloading start 1 1 "" "$(printf 'x%.0s' {1..300})" audio
dots-call downloading progress 37
settled '.mode == "downloading"'
check "a 300-character title elides on one line and the percent is still drawn at the right edge" state_is '.downloading.elided and .downloading.lines == 1 and (.downloading.right - (.drawn - 16) | fabs) <= 1 and (.downloading.line | endswith(" · 37%"))'
dots-call downloading start 1 1 $'Fo\no‮' $'Fea\nther' audio
check "a forged name draws as one line" until_ok 3000 state_is '.downloading.lines == 1 and .text == "↓ Fo o 1 / 1 · Fea ther · 0%"'
dots-call downloading done
exit $((fails > 0))
}
