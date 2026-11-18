#!/usr/bin/env bash
# At motion slowdown 20 every surface's card springs, read from the card as drawn; the launcher and the cheat sheet grow from the island instead, on the island's motion.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

wait_until() { while (($(now_ms) - t0 < $1)); do sleep 0.005; done; }

until_ok 5000 shell_status >/dev/null

# Each card is read as drawn rather than from its Motion.
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
for s in notifs goals control; do springs "$s" "qs ipc call $s open" "qs ipc call $s close"; done
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
