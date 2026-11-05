#!/usr/bin/env bash
# Slowed 20 times, a card's miniature crossfade is seen mid-play: its specimen part way faded in over the picker's paper, then whole at rest.
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
until_ok 3000 bash -c "timeout 0.5 qs ipc call shell status | jq -e '.theme == \"artboard\"' >/dev/null"
niri msg action spawn -- dots-call themes toggle
until_ok 6000 state_is '.open and .settled'

# The preview's last rows, below its windows, are bare paper; the card scales the preview, so the row is read from its drawn height.
bare_y() { themes_state | jq -r '.cards[] | select(.name == "catppuccin-mocha") | .preview.h * 0.97 | floor'; }

# The crossfade runs 5.2 s slowed; 1.6 s in, catppuccin-mocha's card is part way between Artboard's paper and its own.
wtype 2
sleep 1.6
mid=$(stage catppuccin-mocha)
bottom=$(preview_mean catppuccin-mocha 60 "$(bare_y)" 40 2)
check "catppuccin-mocha mid-fade is part way in, at its full size: $mid" jq -e '.opacity > 0.05 and .opacity < 0.95 and .scale == 1 and .h == 196 and .w == 306 and .y == 0' <<<"$mid"
partway() { local v; read -r -a v <<<"$1"; ((v[0] < 220 && v[0] > 25)); }
check "catppuccin-mocha mid-fade: its bare paper reads between #E4E6EA and #11111B ($bottom)" partway "$bottom"
until_ok 8000 state_is '.played.ms >= 0'
check "at rest every card is drawn whole" state_is 'all(.cards[]; .stage == {"y": 0, "h": 196, "w": 306, "opacity": 1, "scale": 1})'
rest=$(preview_mean catppuccin-mocha 60 "$(bare_y)" 40 2)
check "catppuccin-mocha at rest: its bare paper is #11111B ($rest)" near "$rest" "17 17 27" 12

wtype -k Escape
exit $((fails > 0))
}
