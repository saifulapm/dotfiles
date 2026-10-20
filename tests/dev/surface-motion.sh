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
press() { t0=$(now_ms); niri msg action spawn -- dots-call launcher toggle >/dev/null; }
wait_until() { while (($(now_ms) - t0 < $1)); do sleep 0.005; done; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
theme() {
  "$repo/bin/dots" theme "$1" >/dev/null
  until_ok 2000 status_theme "$1"
}

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')
# The launcher card's top-left corner at rest, in screen pixels.
cx=$((ox + (ow - 640 + 1) / 2))
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
niri msg action spawn -- dots-call themes open >/dev/null
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

# Every other surface's card springs too, read from the card as drawn rather than from its Motion.
surface_is() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }
card_w() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -r .cardBox.w; }
# springs <target> <open command> <close command>: the card 300 ms into a 20x open, then at rest.
springs() {
  local w1 w2
  t0=$(now_ms)
  eval "$2" >/dev/null
  wait_until 300
  w1=$(card_w "$1")
  until_ok 9000 surface_is "$1" .settled
  w2=$(card_w "$1")
  check "artboard: 300 ms into a 20x open the $1 card is drawn at 0.98 of its rest width or less ($w1 of $w2)" node -e "process.exit($w1 / $w2 <= 0.98 ? 0 : 1)"
  eval "$3" >/dev/null
  check "artboard: the $1 card still draws as its close plays" surface_is "$1" .drawing
  until_ok 9000 surface_is "$1" '.drawing == false'
}
for s in themes notifs cheatsheet goals control; do springs "$s" "qs ipc call $s open" "qs ipc call $s close"; done
springs record "qs ipc call record toggle" "qs ipc call record toggle"
# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent, as in polkit.sh.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 surface_is polkit .registered
springs polkit "fake Begin s motion" "wtype -k Escape"
# The request's text stays on the card while it sinks, so the close plays the open in reverse.
fake Begin s motion >/dev/null
until_ok 9000 surface_is polkit .settled
message=$(timeout 0.5 qs ipc call polkit state | jq -r .drawnMessage)
wtype -k Escape
until_ok 1000 surface_is polkit '.open == false'
check "artboard: the polkit card keeps drawing its message through the close ($message)" surface_is polkit ".drawing and .drawnMessage == \"$message\" and .drawnMessage != \"\""
until_ok 9000 surface_is polkit '.drawing == false'

theme blueprint
# Pixels in a box brighter than the navy paper, its grid and the card's fill: the cyan pen, the ink text.
bright() {
  grim -s 1 -t ppm -g "$1,$2 $3x$4" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (px[i * 3] + px[i * 3 + 1] + px[i * 3 + 2] > 450) n++;
    console.log(n);
  '
}
press
wait_until 1000
# A plot neither moves nor scales the card, so its drawn height is its height at rest.
read -r card_h < <(launcher_state | jq -r '.cardBox.h | floor')
# The pen starts on the top edge past the chamfer and goes round clockwise, so a second in it has drawn the top but not the left edge.
top_pen=$(bright $((cx + 14)) $((cy - 1)) 200 3)
left_pen=$(bright $((cx - 1)) $((cy + 30)) 3 30)
inside=$(bright $((cx + 10)) $((cy + 10)) 620 60)
check "blueprint: 1 s into a 20x open the outline has drawn its top edge ($top_pen px) and not yet its left ($left_pen px)" test "$top_pen" -ge 150 -a "$left_pen" = 0
check "blueprint: and nothing inside the card is drawn yet ($inside bright px)" test "$inside" = 0
# Near the end of the pen, past the bottom-right corner, it has drawn that corner's bevel and left its square corner bare.
wait_until 2900
bevel=$(bright $((cx + 640 - 9)) $((cy + card_h - 9)) 6 6)
corner=$(bright $((cx + 637)) $((cy + card_h - 3)) 3 3)
# A 12 px rounded corner would bulge 2 to 3 px past the bevel's line here.
bulge=$(bright $((cx + 636)) $((cy + card_h - 5)) 2 2)
inside=$(bright $((cx + 10)) $((cy + 10)) 620 60)
check "blueprint: the pen turns the bottom-right corner along its chamfer ($bevel px on the bevel, $corner on the square corner, $bulge where an arc would run, $inside inside)" test "$bevel" -gt 0 -a "$corner" = 0 -a "$bulge" = 0 -a "$inside" = 0
until_ok 7000 state_is .settled
check "blueprint: the launcher reports a plot that settled in about 20 times 240 ms ($(launcher_state | jq -c '[.motion, .settleMs]'))" state_is '.motion == "plot" and .settleMs >= 4700 and .settleMs <= 5400'
check "blueprint: at rest the card's text is drawn ($(bright $((cx + 10)) $((cy + 10)) 620 60) bright px)" test "$(bright $((cx + 10)) $((cy + 10)) 620 60)" -gt 50
check "blueprint: at rest the pen runs down the left edge below the chamfer and not across its square corner" test "$(bright $((cx - 1)) $((cy + 30)) 3 30)" -gt 0 -a "$(bright "$cx" "$cy" 2 2)" = 0
wtype -k Escape
until_ok 7000 state_is '.drawing == false'

# A theme switch mid-plot carries the open on in Paper's drop, so it ends as a Paper card with no pen left over.
press
wait_until 1000
theme paper
until_ok 7000 state_is .settled
check "blueprint to paper mid-open: it settles as Paper's card, its ink frame at rest" test "$(first_y $((cx + 320)) $((cy - 30)) 60 28 25 21)" = 30
check "blueprint to paper mid-open: the state says drop, timed at Paper's pace rather than Blueprint's 4.8 s ($(launcher_state | jq .settleMs) ms)" state_is '.motion == "drop" and .settleMs < 3600'
wtype -k Escape
until_ok 4000 state_is '.drawing == false'

theme paper
exit $((fails > 0))
}
