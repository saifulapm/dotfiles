#!/usr/bin/env bash
# At the live speed every card surface opens on the one spring (362 ms) and settles in 340 to 400 ms, no sooner than a frame or so short of it.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

surface_is() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }
springs='.motion == "spring" and (.settleMs | type) == "number" and .settleMs >= 340 and .settleMs <= 400'

# Opens surface $1 and checks it settles on the spring, then closes it.
settles() {
  local s=$1
  niri msg action spawn -- dots-call "$s" open >/dev/null
  until_ok 3000 surface_is "$s" .settled
  check "the $s settles as a spring in 340 to 400 ms ($(timeout 0.5 qs ipc call "$s" state | jq -c '[.motion, .settleMs, .firstFrame]'))" surface_is "$s" "$springs"
  timeout 0.5 qs ipc call "$s" close >/dev/null
  until_ok 2000 surface_is "$s" '.drawing == false'
}

until_ok 5000 shell_status >/dev/null
# The launcher, the cheat sheet and Control grow from the island on its own motion, which island-motion.sh times.
for s in notifs goals; do settles "$s"; done

# The recorder's picker opens and closes on its one toggle.
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 3000 surface_is record .settled
check "the recorder's picker settles as a spring in 340 to 400 ms ($(timeout 0.5 qs ipc call record state | jq -c '[.motion, .settleMs]'))" surface_is record ".picking and $springs"
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 2000 surface_is record '.drawing == false'

# pkexec always reaches the live polkitd, so a fake authority on the nested bus asks the nested shell's agent instead.
fake() { busctl --address="$DBUS_SESSION_BUS_ADDRESS" call org.freedesktop.PolicyKit1 /org/freedesktop/PolicyKit1/Authority org.dots.FakePolkit "$@"; }
DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS "$repo/bin/dev-fake-polkit" 9>&- &
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
