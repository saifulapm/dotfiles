#!/usr/bin/env bash
# The launcher's open and close at motion slowdown 20, seen in its pixels: it springs up 8 px from 0.96, a close is shorter and gives the keyboard back at once, and every surface springs.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
sheet_is() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so a press spawns the bind's command through niri.
press() { t0=$(now_ms); niri msg action spawn -- dots-call launcher toggle >/dev/null; }
wait_until() { while (($(now_ms) - t0 < $1)); do sleep 0.005; done; }
focus_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')
# The launcher card's top-left corner at rest, in screen pixels.
cx=$((ox + (ow - 640 + 1) / 2))
cy=$((oy + 168))

rgb() { grim -s 1 -t ppm -g "$1,$2 ${3:-1}x${4:-1}" - | mean_rgb; }
near() { local r g b t=${tol:-24}; read -r r g b < <(rgb "$1" "$2"); ((r - $3 <= t && $3 - r <= t && g - $4 <= t && $4 - g <= t && b - $5 <= t && $5 - b <= t)); }

until_ok 5000 shell_status >/dev/null

before=$(rgb $((cx + 320)) $((cy + 60)))
press
wait_until 300
check "300 ms into a 20x open the drawn card is scaled to 0.98 or less ($(launcher_state | jq -c '.cardBox.w / 640'))" state_is '.cardBox.w / 640 <= 0.98'
check "and it is drawn below its rest, rising to it ($(launcher_state | jq -c '.cardBox.y'))" state_is '.cardBox.y > 168'
# The card's white is still below and inside its rest edge, so the rest top row shows only the wash.
no_white_edge() { ! near $((cx + 100)) $((cy + 3)) 255 255 255; }
check "its rest top edge shows no white card yet" no_white_edge
# The keyboard is the surface's from the first frame, so typing mid-spring reaches the query.
until_ok 3000 state_is '.keyboard'
wtype fo
until_ok 2000 state_is '.query == "fo"'
check "typing during the spring reaches the query whole" state_is '.query == "fo" and .settled == false'
until_ok 9000 state_is .settled
check "the launcher reports a spring that settled in about 20 times 362 ms ($(launcher_state | jq -c '[.motion, .settleMs]'))" state_is '.motion == "spring" and .settleMs >= 7000 and .settleMs <= 8200'
check "at rest the drawn card is where it rests, at full size" state_is '.cardBox.y == 168 and .cardBox.w == 640'
check "at rest the card's top edge is white" near $((cx + 100)) $((cy + 3)) 255 255 255

# Esc gives the keyboard back as the close starts, long before the 5.8 s close is drawn.
t0=$(now_ms)
wtype -k Escape
until_ok 1000 focus_is None
none_ms=$(($(now_ms) - t0))
check "after Esc niri lists the surfaces with keyboard None within 50 ms ($none_ms ms)" test "$none_ms" -le 50
check "the close is still drawing then" state_is '.open == false and .drawing'
check "and the card still covers its centre" test "$(rgb $((cx + 320)) $((cy + 60)))" != "$before"
until_ok 9000 state_is '.drawing == false'
after=$(rgb $((cx + 320)) $((cy + 60)))
check "once the close ends the card's centre reads the paper again ($before, then $after)" test "$after" = "$before"
check "the close took about 20 times 290 ms, shorter than the open ($(launcher_state | jq -c '[.closeTookMs, .settleMs]'))" state_is '.closeTookMs >= 5400 and .closeTookMs <= 6400 and .closeTookMs < .settleMs'

# Open, then close mid-open: it sinks back from where it was and ends closed with the keyboard back.
press
until_ok 3000 state_is '.keyboard'
wait_until 800
press
until_ok 1000 focus_is None
check "pressed twice fast, the second press closes it and gives the keyboard back" state_is '.open == false and .drawing'
until_ok 9000 state_is '.drawing == false'
closed_clean() { state_is '.open == false and .drawing == false' && focus_is None; }
check "the half-open close ends with nothing drawn and no keyboard" closed_clean

# Another surface opening during the close cuts it short, so only the new one shows.
press
until_ok 9000 state_is .settled
wtype -k Escape
until_ok 1000 state_is '.open == false and .drawing'
niri msg action spawn -- dots-call cheatsheet open >/dev/null
until_ok 2000 sheet_is .open
check "opening the cheat sheet mid-close stops the launcher drawing at once" state_is '.drawing == false'
timeout 0.5 qs ipc call cheatsheet close >/dev/null
until_ok 9000 sheet_is '.drawing == false'

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
  check "300 ms into a 20x open the $1 card is drawn at 0.98 of its rest width or less ($w1 of $w2)" node -e "process.exit($w1 / $w2 <= 0.98 ? 0 : 1)"
  eval "$3" >/dev/null
  check "the $1 card still draws as its close plays" surface_is "$1" .drawing
  until_ok 9000 surface_is "$1" '.drawing == false'
}
for s in notifs cheatsheet goals control; do springs "$s" "qs ipc call $s open" "qs ipc call $s close"; done
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
check "the polkit card keeps drawing its message through the close ($message)" surface_is polkit ".drawing and .drawnMessage == \"$message\" and .drawnMessage != \"\""
until_ok 9000 surface_is polkit '.drawing == false'

exit $((fails > 0))
}
