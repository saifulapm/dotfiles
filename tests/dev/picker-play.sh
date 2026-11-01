#!/usr/bin/env bash
# Slowed 20 times, each card's miniature switch is seen mid-play: Blueprint's scan, Hi-Fi's sweep, Artboard's fade and zoom, Paper's slide.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$@" >/dev/null; }
stage() { themes_state | jq -c --arg n "$1" '.cards[] | select(.name == $n) | .stage'; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
# The mean colour of a w x h region at x,y inside card $1's preview.
preview_mean() {
  local x y
  read -r x y < <(themes_state | jq -r --arg n "$1" --argjson ox "$ox" --argjson oy "$oy" '.cards[] | select(.name == $n) | .preview | "\(.x + $ox | round) \(.y + $oy | round)"')
  grim -s 1 -t ppm -g "$((x + $2)),$((y + $3)) ${4}x${5}" - | mean_rgb
}
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 bash -c "timeout 0.5 qs ipc call shell status | jq -e '.theme == \"paper\"' >/dev/null"
niri msg action spawn -- dots-call themes toggle
# Paper's open takes 120 ms, 2.4 s slowed.
until_ok 6000 state_is '.open and .settled'

# Blueprint's scan, 4.4 s slowed: halfway, its bottom rows are still Paper's paper and its top rows its own navy.
wtype 3
sleep 2.2
mid=$(stage blueprint)
bottom=$(preview_mean blueprint 100 182 40 8)
top=$(preview_mean blueprint 100 24 40 4)
check "blueprint mid-scan has drawn part of its card: $mid" jq -e '.h > 40 and .h < 156' <<<"$mid"
check "blueprint mid-scan: the bottom is still Paper's paper ($bottom)" near "$bottom" "241 233 216" 12
check "blueprint mid-scan: the top is already its navy ($top)" near "$top" "12 26 46" 20
until_ok 4000 state_is '.played.ms >= 0'

# Hi-Fi's sweep, 4.4 s slowed: halfway, its dark paper is left of the pointer, Paper's cream right of it, and red pixels sit at the stage's edge.
wtype 4
sleep 2.2
mid=$(stage hi-fi)
left=$(preview_mean hi-fi 20 90 40 8)
right=$(preview_mean hi-fi 250 90 40 8)
# The columns of row 100 of card $1's preview that read #FB4934, as a first and last x.
red_span() {
  local x y
  read -r x y < <(themes_state | jq -r --arg n "$1" --argjson ox "$ox" --argjson oy "$oy" '.cards[] | select(.name == $n) | .preview | "\(.x + $ox | round) \(.y + $oy | round)"')
  grim -s 1 -t ppm -g "$x,$((y + 100)) 306x1" - | node -e '
    const b = require("fs").readFileSync(0);
    const px = b.subarray(b.toString("latin1").match(/^P6\s+\d+\s+\d+\s+\d+\s/)[0].length);
    const xs = [];
    for (let i = 0; i < px.length / 3; i++) if (px[i * 3] > 200 && px[i * 3 + 1] < 110 && px[i * 3 + 2] < 110) xs.push(i);
    console.log(xs.length ? `${xs[0]} ${xs[xs.length - 1]}` : "none");
  '
}
red=$(red_span hi-fi)
w=$(stage hi-fi | jq .w)
check "hi-fi mid-sweep has crossed part of its card: $mid" jq -e '.w > 40 and .w < 266' <<<"$mid"
check "hi-fi mid-sweep: left of the pointer is its dark paper ($left)" near "$left" "29 32 33" 20
check "hi-fi mid-sweep: right of the pointer is still Paper's paper ($right)" near "$right" "241 233 216" 12
check "hi-fi mid-sweep: red pointer pixels lie at the stage's edge ($red, stage $w)" bash -c 'read -r a b <<<"$1"; [[ $a =~ ^[0-9]+$ && $a -ge $(($2 - 30)) && $b -le $(($2 + 30)) ]]' _ "$red" "${w%.*}"
until_ok 4000 state_is '.played.ms >= 0'

# Artboard's zoom fades its card in over 4.4 s.
wtype 2
sleep 1.1
mid=$(stage artboard)
check "artboard mid-zoom is fading in and scaled: $mid" jq -e '.opacity > 0.05 and .opacity < 0.95 and .scale < 1' <<<"$mid"
until_ok 4000 state_is '.played.ms >= 0'

# Paper's slide eases out over 4.4 s; early on its card is still below its place.
wtype 1
sleep 0.2
mid=$(stage paper)
check "paper mid-slide is below its place: $mid" jq -e '.y > 10' <<<"$mid"
until_ok 6000 state_is '.played.ms >= 0'
check "at rest every card is drawn whole" state_is 'all(.cards[]; .stage == {"y": 0, "h": 196, "w": 306, "opacity": 1, "scale": 1})'

wtype -k Escape
exit $((fails > 0))
}
