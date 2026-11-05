#!/usr/bin/env bash
# At the live speed every surface opens on the one spring (362 ms) and settles in 340 to 400 ms, no sooner than a frame or so short of it; the launcher's close is shorter than its open.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

surface_is() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }
# A first open draws its first frame near the start of its motion, not halfway through.
from_start() { surface_is "$1" '(.firstFrame | type) == "number" and .firstFrame > 0 and .firstFrame <= 0.3'; }
springs='.motion == "spring" and (.settleMs | type) == "number" and .settleMs >= 340 and .settleMs <= 400'

# Opens surface $1 and checks it settles on the spring, then closes it.
settles() {
  local s=$1
  niri msg action spawn -- dots-call "$s" open >/dev/null
  until_ok 3000 surface_is "$s" .settled
  check "the $s settles as a spring in 340 to 400 ms ($(timeout 0.5 qs ipc call "$s" state | jq -c '[.motion, .settleMs, .firstFrame]'))" surface_is "$s" "$springs"
  case $s in cheatsheet | control) check "the $s draws its first frame near the start of its open" from_start "$s" ;; esac
  timeout 0.5 qs ipc call "$s" close >/dev/null
  until_ok 2000 surface_is "$s" '.drawing == false'
}

until_ok 5000 shell_status >/dev/null
for s in launcher themes notifs cheatsheet goals control; do settles "$s"; done
# The launcher times its own close: 0.8 of the open's 362 ms, 290, less a frame or so.
check "the launcher's close took 260 to 330 ms, shorter than its open ($(timeout 0.5 qs ipc call launcher state | jq -c '[.closeTookMs, .settleMs, .motionMs]'))" \
  surface_is launcher '.closeTookMs >= 260 and .closeTookMs <= 330 and .closeTookMs < .settleMs and .motionMs.close < .motionMs.open'

# The recorder's picker opens and closes on its one toggle.
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 3000 surface_is record .settled
check "the recorder's picker settles as a spring in 340 to 400 ms ($(timeout 0.5 qs ipc call record state | jq -c '[.motion, .settleMs]'))" surface_is record ".picking and $springs"
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 2000 surface_is record '.drawing == false'

# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
until_ok 3000 fake Registered >/dev/null 2>&1
# The agent registers as the shell starts, so the shell restarts once the authority is up.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 5000 surface_is polkit .registered

# A request opens the polkit prompt and Esc cancels it.
fake Begin s settle >/dev/null
until_ok 3000 surface_is polkit .settled
check "the polkit prompt settles as a spring in 340 to 400 ms ($(timeout 0.5 qs ipc call polkit state | jq -c '[.motion, .settleMs]'))" surface_is polkit ".open and $springs"
wtype -k Escape
until_ok 2000 surface_is polkit '.drawing == false'

exit $((fails > 0))
}
