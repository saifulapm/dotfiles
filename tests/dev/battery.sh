#!/usr/bin/env bash
# The resting island's battery word, from a UPower double on the nested bus that stands in for the system bus.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }

no_battery() { island | jq -e '.rest.battery == null' >/dev/null; }
echo "     island with no UPower: $(island | jq -c .rest)"
check "with no UPower the resting island shows no battery" no_battery

"$repo/bin/dev-fake-upower" 9>&- &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
fake_up() { busctl --user status org.freedesktop.UPower >/dev/null 2>&1; }
until_ok 5000 fake_up
check "the UPower double owns its name on the nested bus" fake_up

# Quickshell looks for UPower once, when the shell starts, so the shell restarts to find the double.
systemctl --user restart "$DOTS_DEV_UNIT"
surfaces_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
until_ok 10000 surfaces_mapped
until_ok 5000 shell_status >/dev/null
until_ok 6000 at_rest

battery_is() { island | jq -e --arg b "$1" '.rest.battery == $b' >/dev/null 2>&1; }
until_ok 5000 battery_is "82%"
echo "     island: $(island | jq -c .rest)"
check "the battery reads 82% while discharging" battery_is "82%"

status=$(shell_status)
echo "     status: $status"
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "status still reports one running timer" one_timer

# Asahi does not suspend, so nothing but this notice stands between a low battery and a dead MacBook.
set_battery() { busctl --user call org.freedesktop.UPower /org/freedesktop/UPower org.dots.FakeUPower Set db "$1" "$2"; }
lows() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq '[.summaries[] | select(. == "Battery low")] | length'; }
lows_is() { [ "$(lows)" = "$1" ]; }
set_battery 9 false
until_ok 3000 lows_is 1
check "at 9% discharging a notice says the battery is low ($(lows))" lows_is 1
set_battery 8 false
sleep 1
check "at 8% it does not warn again ($(lows))" lows_is 1
set_battery 20 false
sleep 0.5
set_battery 10 false
until_ok 3000 lows_is 2
check "past 15% and back to 10% it warns again ($(lows))" lows_is 2
set_battery 82 false

# Read last, so it covers the shell both before and after the restart.
journal() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat; }
# The nested bus has no NetworkManager, and Quickshell's Networking says so once per start; any other line is ours.
errors=$(journal | grep -E 'ERROR|Failed to load|TypeError|ReferenceError|is not a type|Cannot assign|Cannot read|quickshell\.network' | grep -vF 'Network will not work. Could not find an available backend.')
echo "     UPower warnings: $(journal | grep -c 'quickshell.service.upower')"
check "the shell's journal has no errors" test -z "$errors"
[ -z "$errors" ] || echo "$errors"

exit $((fails > 0))
}
