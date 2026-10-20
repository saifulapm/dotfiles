#!/usr/bin/env bash
# The top-right battery and wifi words, from a UPower double on the nested bus that stands in for the system bus.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }

today=$(LC_ALL=C date '+%a %-d %b')
just_date() { margins | jq -e --arg d "$today" '.right.text == $d' >/dev/null; }
echo "     margins with no UPower or NetworkManager: $(margins | jq -c .right)"
check "the top-right is just the date ($today)" just_date

"$repo/bin/dev-fake-upower" &
fake_pid=$!
cleanup() { kill "$fake_pid" 2>/dev/null; }
fake_up() { busctl --user status org.freedesktop.UPower >/dev/null 2>&1; }
until_ok 5000 fake_up
check "the UPower double owns its name on the nested bus" fake_up

# Quickshell looks for UPower once, when the shell starts, so the shell restarts to find the double.
systemctl --user restart "$DOTS_DEV_UNIT"
margins_mapped() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
until_ok 10000 margins_mapped
until_ok 5000 shell_status >/dev/null

battery_is() { margins | jq -e --arg b "$1" '.right.battery == $b' >/dev/null 2>&1; }
until_ok 5000 battery_is "82%"
echo "     margins: $(margins | jq -c .right)"
check "the battery reads 82% while discharging" battery_is "82%"

busctl --user call org.freedesktop.UPower /org/freedesktop/UPower org.dots.FakeUPower Set db 82 true
start=$(now_ms)
# No sleep between reads, so the poll adds no delay of its own.
until battery_is "82% charging"; do (($(now_ms) - start < 2000)) || break; done
elapsed=$(($(now_ms) - start))
echo "     margins: $(margins | jq -c .right)"
check "the battery reads 82% charging ${elapsed} ms after the double switched" battery_is "82% charging"
check "the switch showed within 2000 ms" test "$elapsed" -le 2000

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
