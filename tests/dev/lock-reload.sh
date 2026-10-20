#!/usr/bin/env bash
# A hot reload while locked keeps the session locked: the new tree relocks, draws its clock, and only the password unlocks.
{
repo=$(cd "$(dirname "$0")/../.." && pwd)
# The nested shell runs a copy, so this check's edit never reaches the shell/ the live shell watches.
copy=$(mktemp -d)
cp -a "$repo/shell" "$copy/shell"
ln -s "$repo/bin" "$copy/bin"
export DOTS_DEV_SHELL=$copy/shell
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$copy"; }

shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
lock_state() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call lock state 2>/dev/null; }
state_is() { lock_state | jq -e "$1" >/dev/null 2>&1; }
locked_shown() { state_is '.locked and .secure'; }
# Dark pixels in the band where the lock draws its clock: the paper alone has none.
clock_ink() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 4 | floor)),\(.y + (.height / 5 | floor)) \(.width / 2 | floor)x\(.height * 3 / 10 | floor)"')
  grim -s 1 -t ppm -g "$geo" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) if (px[i] < 80 && px[i + 1] < 80 && px[i + 2] < 80) n++;
    console.log(n);
  '
}

paper_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper")' >/dev/null; }
until_ok 5000 paper_up
config=$(tr '\0' '\n' <"/proc/$(shell_pid)/environ" | sed -n 's/^QS_CONFIG_PATH=//p')
check "the nested shell runs a copy, not $repo/shell" test -n "$config" -a "$config" != "$repo/shell"
until_ok 5000 state_is '.locked == false'
ink_before=$(clock_ink)

niri msg action spawn -- dots-call lock lock
until_ok 3000 locked_shown
check "the shell locks" locked_shown

# qs skips a change that leaves the bytes the same, so the copy gets a new line.
echo "// reload 1" >>"$config/shell.qml"
loads() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -c 'Configuration Loaded'; }
reloaded() { (($(loads) >= 2)); }
check "the shell reloads" until_ok 5000 reloaded
until_ok 3000 locked_shown
check "the reloaded shell holds the lock" locked_shown
ink_after=$(clock_ink)
check "the reloaded lock draws its clock ($ink_before dark px before, $ink_after after)" test "$ink_after" -gt $((ink_before + 500))

wtype -- dots-test-pass
wtype -k Return
until_ok 3000 state_is '.locked == false'
check "the test password unlocks after the reload" state_is '.locked == false'

exit $((fails > 0))
}
