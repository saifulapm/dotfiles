#!/usr/bin/env bash
# A Lock.qml broken mid-edit fails the hot reload, so the working lock stays: it still locks and the password still unlocks.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy, so this check's edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
ln -s "$repo/bin" "$copy/bin"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$copy"; }
# The breakage is on purpose, so its own errors are left out of the journal check.
qml_errors() {
  journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat 2>/dev/null |
    grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load configuration|is not a type|Cannot assign|Cannot read propert' |
    grep -vE 'Lock\.qml|Failed to load configuration'
}

shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
lock_state() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call lock state 2>/dev/null; }
state_is() { lock_state | jq -e "$1" >/dev/null 2>&1; }
locked_shown() { state_is '.locked and .secure'; }

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
until_ok 5000 paper_up
config=$(tr '\0' '\n' <"/proc/$(shell_pid)/environ" | sed -n 's/^QS_CONFIG_PATH=//p')
check "the nested shell runs a copy, not $repo/shell" test -n "$config" -a "$config" != "$repo/shell"
until_ok 5000 state_is '.locked == false'

echo "this is not qml {" >>"$config/Lock.qml"
failed() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -q 'Lock\.qml'; }
check "qs reports the broken Lock.qml" until_ok 5000 failed
# qs answers no query for a few seconds after a failed reload, then the old tree answers again.
check "the old tree's lock answers again" until_ok 10000 state_is '.locked == false'

niri msg action spawn -- qs ipc call lock lock
until_ok 3000 locked_shown
check "the shell still locks" locked_shown
wtype -- dots-test-pass
wtype -k Return
until_ok 3000 state_is '.locked == false'
check "the test password still unlocks" state_is '.locked == false'

exit $((fails > 0))
}
