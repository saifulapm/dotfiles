#!/usr/bin/env bash
# The local hub's presence flags in $XDG_STATE_HOME/qshell follow the session: idle while dimmed, locked while locked or leased, and a restart clears what no state holds.
{
source "$(dirname "$0")/lib.sh"

flags=$DOTS_DEV_DIR/state/qshell
idle_is() { timeout 0.5 qs ipc call idle state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
locked() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e .locked >/dev/null 2>&1; }
has() { [ -e "$flags/$1" ]; }
hasnt() { [ ! -e "$flags/$1" ]; }
field_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e ".secure and .field == $1" >/dev/null 2>&1; }
# A fresh lock can drop the first keys typed into it, so a field short of the 14 characters is refused and typed again.
unlock() {
  local _
  for _ in 1 2 3; do
    until_ok 3000 field_is 0
    wtype dots-test-pass
    until_ok 1000 field_is 14 && break
    wtype -k Return
  done
  wtype -k Return
  until_ok 3000 bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
}

until_ok 5000 shell_status >/dev/null
until_ok 2000 test -d "$flags"
check "at rest neither idle nor locked stands" bash -c "[ ! -e '$flags/idle' ] && [ ! -e '$flags/locked' ]"

# Dim at 3 s, lock at 5 s; no key reaches the nested niri until then.
timeout 0.5 qs ipc call idle times 3 5 60 >/dev/null
until_ok 6000 idle_is .dimmed
until_ok 1000 has idle
check "dimmed, idle stands" has idle
check "but not locked yet" hasnt locked
until_ok 4000 locked
until_ok 1000 has locked
check "locked, locked stands" has locked
idle_at=$(stat -c %Y "$flags/idle")
sleep 1.5
check "idle keeps the time it began" test "$(stat -c %Y "$flags/idle")" = "$idle_at"

timeout 0.5 qs ipc call idle times 240 300 360 >/dev/null
unlock
until_ok 2000 idle_is '.dimmed | not'
until_ok 1000 hasnt locked
until_ok 1000 hasnt idle
check "unlocked, locked is gone" hasnt locked
check "the dim lifted, idle is gone" hasnt idle

# An agent's lease leaves the session unlocked with no one at the screen.
niri msg action spawn -- dots-call lock lock
until_ok 3000 locked
timeout 0.5 qs ipc call lock unlock claude 1 >/dev/null
until_ok 3000 bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
check "unlocked on a lease, locked stands" has locked
niri msg action spawn -- dots-call lock lock
until_ok 3000 locked
unlock
until_ok 1000 hasnt locked
check "unlocked by the password, locked is gone" hasnt locked

# A flag left by a shell that stopped, or by v1's, goes at the next start.
: >"$flags/idle"
: >"$flags/stay-awake"
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 8000 shell_status >/dev/null
until_ok 2000 hasnt idle
check "a restart clears a stale idle" hasnt idle
check "and v1's stay-awake" hasnt stay-awake

exit $((fails > 0))
}
