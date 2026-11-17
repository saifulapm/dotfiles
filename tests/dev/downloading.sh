#!/usr/bin/env bash
# A YouTube download takes the island's slot with its title, place in a Playlist, percent and a bar; a failure holds 5 s over it, and a send outranks it.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
state_is() { island | jq -e "$@" >/dev/null 2>&1; }
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
check "at rest the island is the clock" state_is '.mode == "rest" and .live == null'
check "a percent before any start is dropped" bash -c 'dots-call downloading progress 30 && sleep 0.3 && ! timeout 0.5 qs ipc call island state | jq -e ".mode == \"downloading\"" >/dev/null'
dots-call downloading start 3 18 Focus Feather audio
dots-call downloading progress 37

settled '.mode == "downloading"'
echo "     downloading: $(island | jq -c '{text, width, drawn, live}')"
check "island state reports mode downloading and the line" state_is '.mode == "downloading" and .text == "↓ Focus 3 / 18 · Feather · 37%"'
check "the line draws a download icon, 3 / 18 and 37%, the clock at the right, in 34 px" state_is --arg i "$(printf '\U000F01DA')" '.live.icon == $i and .live.text == "3 / 18" and .live.tail == "37%" and (.live.elided | not) and .live.tone == "normal" and .live.clockRight == 14 and .height == 34'
check "the bar is filled to 37% of its width" state_is '(.live.bar.width | type == "number") and .live.bar.fill >= (.live.bar.width * 0.35) and .live.bar.fill <= (.live.bar.width * 0.39)'
area=$(island | jq '(.live.bar.fill * 6 * 0.8) | floor')
ink=$(island | jq -r '.live.ink | ascii_upcase')
check "the bar's fill, the island's on colour $ink, is drawn over its area ($area px)" test "$(near $(rgb "$ink"))" -ge "$area"

dots-call downloading progress 80
check "progress moves the drawn percent and the fill" until_ok 3000 state_is '.live.tail == "80%" and .live.bar.fill >= (.live.bar.width * 0.78) and .live.bar.fill <= (.live.bar.width * 0.82)'
notify-send -a Test "over the download" "a"
check "a notification shows over the download" until_ok 3000 state_is '.mode == "notification"'
check "and the download comes back once it has gone" until_ok 8000 state_is '.mode == "downloading" and .live.text == "3 / 18" and .live.tail == "80%"'
dots-call sending start 1 nuc
check "a send outranks the download" until_ok 3000 state_is '.mode == "sending"'
dots-call sending done
check "and the download comes back when the send is done" until_ok 3000 state_is '.mode == "downloading"'
dots-call downloading done
check "done brings the clock back" until_ok 3000 state_is '.mode == "rest" and .live == null'

# A failure holds 5 s over a start that arrives meanwhile, then the download underneath shows.
t0=$(now_ms)
dots-call downloading failed Feather "HTTP 403"
dots-call downloading start 4 18 Focus Next audio
settled '.mode == "downloading"'
since=$(island | jq .since)
check "a failure is drawn as it is told, with no bar" state_is '.live.tone == "danger" and .live.text == "Feather · HTTP 403" and .live.bar == null'
sleep $(awk -v t0="$t0" -v now="$(now_ms)" 'BEGIN { s = 4 - (now - t0) / 1000; print (s > 0 ? s : 0) }')
check "and still at 4 s, in the same mode it began" state_is --argjson s "$since" '.live.text == "Feather · HTTP 403" and .since == $s'
check "at about 5 s the download underneath shows" until_ok 3000 state_is '.live.text == "4 / 18" and .live.tail == "0%"'
took=$(($(now_ms) - t0))
check "the hold lasted about 5 s (took $took ms)" test "$took" -ge 4800 -a "$took" -le 6500
dots-call downloading done

# done does not cut a held failure short.
t0=$(now_ms)
dots-call downloading failed X y
dots-call downloading done
sleep 3.5
check "a failure survives done while it is held" state_is '.mode == "downloading" and .live.tone == "danger"'
check "and the island returns to rest after its 5 s" until_ok 3000 state_is '.mode == "rest" and .live == null'
took=$(($(now_ms) - t0))
check "the hold lasted about 5 s (took $took ms)" test "$took" -ge 4800 -a "$took" -le 6500

# The failure draws as a chip.
dots-call downloading failed Feather "HTTP 403"
settled '.mode == "downloading"'
check "the failure is a red alert icon, then the title and why" state_is --arg i "$(printf '\U000F0028')" '.live.icon == $i and .live.tone == "danger" and .live.text == "Feather · HTTP 403"'
until_ok 8000 state_is '.mode == "rest"'

# A single download reads without a place, and a forged or long title elides before the percent.
dots-call downloading start 1 1 "" Feather audio
settled '.mode == "downloading"'
check "a single download reads its title and 0%" state_is '.text == "↓ Feather · 0%" and .live.text == "Feather" and .live.tail == "0%"'
dots-call downloading start 1 1 "" "$(printf 'x%.0s' {1..300})" audio
dots-call downloading progress 37
settled '.mode == "downloading"'
check "a 300-character title elides on one line, the percent still drawn and the clock at the right edge" state_is '.live.elided and .live.tail == "37%" and .live.clockRight == 14 and .width == 560'
dots-call downloading start 1 1 $'Fo\no‮' $'Fea\nther' audio
check "a forged name draws as one line" until_ok 3000 state_is '.live.text == "1 / 1" and .text == "↓ Fo o 1 / 1 · Fea ther · 0%"'
dots-call downloading done
exit $((fails > 0))
}
