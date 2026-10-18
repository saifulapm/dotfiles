#!/usr/bin/env bash
# The top-right battery and wifi words, from a UPower double on the nested bus that stands in for the system bus.
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

# Read last, so it covers the shell both before and after the restart.
journal() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat; }
# The nested bus has no NetworkManager, and Quickshell's Networking says so once per start; any other line is ours.
errors=$(journal | grep -E 'ERROR|Failed to load|TypeError|ReferenceError|is not a type|Cannot assign|Cannot read|quickshell\.network' | grep -vF 'Network will not work. Could not find an available backend.')
echo "     UPower warnings: $(journal | grep -c 'quickshell.service.upower')"
check "the shell's journal has no errors" test -z "$errors"
[ -z "$errors" ] || echo "$errors"

exit $((fails > 0))
