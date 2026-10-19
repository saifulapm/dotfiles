#!/usr/bin/env bash
# The launcher's open and close at motion slowdown 20, seen in its pixels: Paper drops, Artboard springs, a close gives the keyboard back at once.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
themes_is() { timeout 0.5 qs ipc call themes state 2>/dev/null | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so a press spawns the bind's command through niri.
press() { t0=$(now_ms); niri msg action spawn -- qs ipc call launcher toggle >/dev/null; }
wait_until() { while (($(now_ms) - t0 < $1)); do sleep 0.005; done; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
theme() {
  "$repo/bin/dots" theme "$1" >/dev/null
  until_ok 2000 status_theme "$1"
}

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')
# The launcher card's top-left corner at rest, in screen pixels.
cx=$((ox + (ow - 640) / 2))
cy=$((oy + 168))

rgb() { grim -s 1 -t ppm -g "$1,$2 ${3:-1}x${4:-1}" - | mean_rgb; }
near() { local r g b t=${tol:-24}; read -r r g b < <(rgb "$1" "$2"); ((r - $3 <= t && $3 - r <= t && g - $4 <= t && $4 - g <= t && b - $5 <= t && $5 - b <= t)); }
# The first y in a column from y0 down whose pixel is within 24 per channel of a colour, or -1.
first_y() {
  grim -s 1 -t ppm -g "$1,$2 1x$3" - | node -e '
    const b = require("fs").readFileSync(0), want = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let y = -1;
    for (let i = 0; i < head[2] && y < 0; i++) if ([0, 1, 2].every((c) => Math.abs(px[i * 3 + c] - want[c]) <= 24)) y = i;
    console.log(y);
  ' "${@:4}"
}

until_ok 5000 shell_status >/dev/null

theme paper
before=$(rgb $((cx + 320)) $((cy + 60)))
press
wait_until 200
# Paper's card is cream inside a 1.5 px ink frame; the frame's top row is where the card is drawn.
top=$(first_y $((cx + 320)) $((cy - 30)) 60 28 25 21)
lift=$((cy - (cy - 30 + top)))
check "paper: 200 ms into a 20x open the card's ink frame sits 3 px or more above its rest, at full ink ($lift px)" test "$top" -ge 0 -a "$lift" -ge 3
until_ok 5000 state_is .settled
check "paper: the launcher reports a drop that settled in about 20 times 120 ms ($(launcher_state | jq -c '[.motion, .settleMs]'))" state_is '.motion == "drop" and .settleMs >= 2300 and .settleMs <= 3000'
check "paper: at rest the drawn card is where it was before the motion" state_is ".cardBox.y == $cy"
check "paper: at rest its frame's top row is at y $cy" test "$(first_y $((cx + 320)) $((cy - 30)) 60 28 25 21)" = 30

# Esc gives the keyboard back as the close starts, long before the 1.9 s close is drawn.
t0=$(now_ms)
wtype -k Escape
until_ok 1000 focus_is None
none_ms=$(($(now_ms) - t0))
check "paper: after Esc niri lists the surfaces with keyboard None within 50 ms ($none_ms ms)" test "$none_ms" -le 50
check "paper: the close is still drawing then" state_is '.open == false and .drawing'
check "paper: and the card still covers its centre" test "$(rgb $((cx + 320)) $((cy + 60)))" != "$before"
until_ok 4000 state_is '.drawing == false'
after=$(rgb $((cx + 320)) $((cy + 60)))
check "paper: once the close ends the card's centre reads the paper again ($before, then $after)" test "$after" = "$before"

# Open, then close mid-open: it sinks back from where it was and ends closed with the keyboard back.
press
until_ok 3000 state_is '.keyboard'
wait_until 800
press
until_ok 1000 focus_is None
check "paper: pressed twice fast, the second press closes it and gives the keyboard back" state_is '.open == false and .drawing'
until_ok 3000 state_is '.drawing == false'
closed_clean() { state_is '.open == false and .drawing == false' && focus_is None; }
check "paper: the half-open close ends with nothing drawn and no keyboard" closed_clean

# Another surface opening during the close cuts it short, so only the new one shows.
press
until_ok 5000 state_is .settled
wtype -k Escape
until_ok 1000 state_is '.open == false and .drawing'
niri msg action spawn -- qs ipc call themes open >/dev/null
until_ok 2000 themes_is .open
check "paper: opening the theme picker mid-close stops the launcher drawing at once" state_is '.drawing == false'
timeout 0.5 qs ipc call themes close >/dev/null

theme artboard
press
wait_until 300
check "artboard: 300 ms into a 20x open the drawn card is scaled to 0.98 or less ($(launcher_state | jq -c '.cardBox.w / 640'))" state_is '.cardBox.w / 640 <= 0.98'
# The card's white is still below and inside its rest edge, so the rest top row shows only the wash.
no_white_edge() { ! near $((cx + 100)) $((cy + 3)) 255 255 255; }
check "artboard: its rest top edge shows no white card yet" no_white_edge
# The keyboard is the surface's from the first frame, so typing mid-spring reaches the query.
until_ok 3000 state_is '.keyboard'
wtype fo
until_ok 2000 state_is '.query == "fo"'
check "artboard: typing during the spring reaches the query whole" state_is '.query == "fo" and .settled == false'
until_ok 9000 state_is .settled
check "artboard: the launcher reports a spring that settled in about 20 times 362 ms ($(launcher_state | jq -c '[.motion, .settleMs]'))" state_is '.motion == "spring" and .settleMs >= 7000 and .settleMs <= 8200'
check "artboard: at rest the card's top edge is white" near $((cx + 100)) $((cy + 3)) 255 255 255
wtype -k Escape
until_ok 9000 state_is '.drawing == false'

theme paper
exit $((fails > 0))
}
