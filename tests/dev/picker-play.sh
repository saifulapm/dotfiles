#!/usr/bin/env bash
# Slowed 20 times, each card's miniature switch is seen mid-play: Blueprint's scan, Artboard's fade and zoom, Paper's slide.
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
niri msg action spawn -- qs ipc call themes toggle
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
check "at rest every card is drawn whole" state_is 'all(.cards[]; .stage == {"y": 0, "h": 196, "opacity": 1, "scale": 1})'

wtype -k Escape
exit $((fails > 0))
}
