#!/usr/bin/env bash
# The local hub's presence flags in $XDG_STATE_HOME/qshell follow the session: idle while dimmed, locked while locked or leased, and a restart clears what no state holds. Claude Code's presence marker stands only while neither does, and goes when the shell's unit stops.
{
source "$(dirname "$0")/lib.sh"

flags=$DOTS_DEV_DIR/state/qshell
present=$DOTS_DEV_DIR/dots-present
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
check "the dev shell's marker is the one it was handed, never the live runtime dir's" test "$(systemctl --user show -p Environment --value "$DOTS_DEV_UNIT" | tr ' ' '\n' | sed -n 's/^CLAUDE_CLIENT_PRESENCE_FILE=//p')" = "$present"
until_ok 2000 test -e "$present"
check "at rest the presence marker stands" test -e "$present"

# Dim at 3 s, lock at 5 s; no key reaches the nested niri until then.
timeout 0.5 qs ipc call idle times 3 5 60 >/dev/null
until_ok 6000 idle_is .dimmed
until_ok 1000 has idle
check "dimmed, idle stands" has idle
check "dimmed, the presence marker is gone" test ! -e "$present"
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
until_ok 1000 test -e "$present"
check "unlocked and lit, the presence marker is back" test -e "$present"

# An agent's lease leaves the session unlocked with no one at the screen.
niri msg action spawn -- dots-call lock lock
until_ok 3000 locked
timeout 0.5 qs ipc call lock unlock claude 1 >/dev/null
until_ok 3000 bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
check "unlocked on a lease, locked stands" has locked
check "unlocked on a lease, the presence marker stays gone" test ! -e "$present"
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

# A shell that stopped can no longer say anyone is at the screen.
until_ok 2000 test -e "$present"
check "after the restart the presence marker stands again" test -e "$present"
systemctl --user stop "$DOTS_DEV_UNIT"
check "a stopped shell leaves no presence marker" test ! -e "$present"

exit $((fails > 0))
}
