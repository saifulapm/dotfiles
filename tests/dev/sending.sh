#!/usr/bin/env bash
# A Taildrop send takes the island's slot with what goes where, its percent and a bar, until its done; a notification shows over it.
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
check "at rest the island is the clock" state_is '.mode == "rest" and .sending == null'
check "a percent before any start is dropped" bash -c 'dots-call sending progress 30 && sleep 0.3 && ! timeout 0.5 qs ipc call island state | jq -e ".mode == \"sending\"" >/dev/null'
dots-call sending start 2 nuc
dots-call sending progress 48

settled '.mode == "sending"'
echo "     sending: $(island | jq -c '{text, width, drawn, sending}')"
check "island state reports mode sending with 48%" state_is '.mode == "sending" and (.text | contains("48%"))'
check "the slot draws what goes where and 48% at its 380 px" state_is '.sending.label == "Sending 2 files to nuc · 48%" and .drawn == 380 and .sending.lines == 1 and .sending.right == (.drawn - 16)'
# The bar's fill is drawn 48% of the slot's width, and a slot at 0% or 100% would fail either bound.
check "the bar is filled to 48% of its width" state_is '(.sending.barWidth | type == "number") and .sending.barFill >= (.sending.barWidth * 0.46) and .sending.barFill <= (.sending.barWidth * 0.50)'
# The fill's colour over most of the fill's own area, which neither the mark nor the words could draw alone.
area=$(island | jq '(.sending.barFill * .sending.barHeight * 0.8) | floor')
check "the bar's fill colour #6C83FF is drawn over its area ($area px)" test "$(near $(rgb '#6C83FF'))" -ge "$area"

dots-call sending progress 100
settled '.mode == "sending"'
check "progress moves the drawn percent and fills the bar" state_is '.sending.label == "Sending 2 files to nuc · 100%" and .sending.barFill == .sending.barWidth'
notify-send -a Tailscale "Sent 2 files to nuc" "a.txt"
check "a notification shows over the send" until_ok 3000 state_is '.mode == "notification"'
check "and the send comes back once it has gone" until_ok 8000 state_is '.mode == "sending"'
dots-call sending done
check "done brings the clock back" until_ok 3000 state_is '.mode == "rest" and .sending == null'

dots-call sending start 1 $'nu\nc‮'"$(printf 'x%.0s' {1..200})"
settled '.mode == "sending"'
check "a forged machine name draws as one line, elided before the bar" state_is '.sending.lines == 1 and .sending.elided and .sending.right == (.drawn - 16)'
dots-call sending done
exit $((fails > 0))
}
