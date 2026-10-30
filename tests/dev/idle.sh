#!/usr/bin/env bash
# Idle steps at test times of 4, 5 and 6 s: dim, then lock, then monitors off; a window holding an idle inhibitor stops all three.
{
source "$(dirname "$0")/lib.sh"

idle_state() { timeout 0.5 qs ipc call idle state 2>/dev/null; }
lock_state() { timeout 0.5 qs ipc call lock state 2>/dev/null; }
idle_is() { idle_state | jq -e "$1" >/dev/null 2>&1; }
locked() { lock_state | jq -e .locked >/dev/null 2>&1; }
# Seconds from $1 (ms) to now, one decimal.
since() { node -e 'console.log(((Date.now() - process.argv[1]) / 1000).toFixed(1))' "$1"; }
within() { node -e 'const [v, lo, hi] = process.argv.slice(1).map(Number); process.exit(v >= lo && v <= hi ? 0 : 1)' "$@"; }

until_ok 5000 shell_status >/dev/null
check "the real idle times are 4, 5 and 6 min" idle_is '.times == [240, 300, 360]'

# No key or pointer reaches the nested niri from here until the steps have run.
t0=$(now_ms)
timeout 0.5 qs ipc call idle times 4 5 6 >/dev/null
dim_at= lock_at= off_at=
until [ -n "$off_at" ] || (($(now_ms) - t0 > 12000)); do
  s=$(idle_state)
  [ -z "$dim_at" ] && jq -e .dimmed <<<"$s" >/dev/null && dim_at=$(since "$t0")
  [ -z "$lock_at" ] && locked && lock_at=$(since "$t0")
  [ -z "$off_at" ] && jq -e '.monitorsOff > 0' <<<"$s" >/dev/null && off_at=$(since "$t0")
  sleep 0.1
done
echo "     dimmed at ${dim_at:-never} s, locked at ${lock_at:-never} s, monitors off at ${off_at:-never} s"
check "it dims at 4 s" within "${dim_at:-99}" 3.5 4.9
check "it locks at 5 s" within "${lock_at:-99}" 4.5 5.9
check "it asks niri to turn the monitors off at 6 s" within "${off_at:-99}" 5.5 6.9

timeout 0.5 qs ipc call idle times 240 300 360 >/dev/null
wtype dots-test-pass
wtype -k Return
until_ok 3000 bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
check "the test password unlocks" bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
until_ok 2000 idle_is '.dimmed | not'
check "input lifts the dim" idle_is '.dimmed | not'

# An agent's lease holds the session unlocked through idle, until the lease's own end.
niri msg action spawn -- dots-call lock lock
until_ok 3000 locked
timeout 0.5 qs ipc call lock unlock claude 1 >/dev/null
ends=$(lock_state | jq .leaseUntil)
timeout 0.5 qs ipc call idle times 3 5 7 >/dev/null
relocked_at=
until [ -n "$relocked_at" ] || (($(now_ms) > ends + 5000)); do
  locked && relocked_at=$(now_ms)
  sleep 0.2
done
check "idle at 5 s does not lock during a 1 min lease ($(((${relocked_at:-0} - ends) / 1000)) s from its end)" test "${relocked_at:-0}" -ge "$((ends - 500))"
check "the lease's end locks" locked
timeout 0.5 qs ipc call idle times 240 300 360 >/dev/null
wtype dots-test-pass
wtype -k Return
until_ok 3000 bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"

# Stay awake holds every step off, shows its end in the margin, and its end brings fresh steps.
margins_right() { timeout 0.5 qs ipc call margins state 2>/dev/null | jq -r .right.text; }
timeout 0.5 qs ipc call idle awake 1 >/dev/null
check "dots awake 1 holds for a minute" idle_is '(.awakeUntil - now * 1000) / 1000 | . > 55 and . <= 60'
check "the margin reads awake and its end ($(margins_right))" bash -c "timeout 0.5 qs ipc call margins state | jq -e '.right.text | test(\"^awake [0-9]{2}:[0-9]{2}  \")' >/dev/null"
before=$(idle_state | jq .monitorsOff)
timeout 0.5 qs ipc call idle times 4 5 6 >/dev/null
sleep 8
check "awake, nothing dims in 8 s" idle_is '.dimmed | not'
check "nothing locks" bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
check "and the monitors stay on" idle_is ".monitorsOff == $before"
t0=$(now_ms)
"$repo/bin/dots" awake off >/dev/null
check "dots awake off ends it" idle_is '.awakeUntil == 0'
check "and the margin drops the word ($(margins_right))" bash -c "! timeout 0.5 qs ipc call margins state | jq -e '.right.text | startswith(\"awake\")' >/dev/null"
until_ok 6000 idle_is .dimmed
dim_at=$(since "$t0")
echo "     dimmed ${dim_at} s after awake off"
check "the fresh steps dim 4 s after it ends" within "$dim_at" 3.5 4.9
timeout 0.5 qs ipc call idle times 240 300 360 >/dev/null
until_ok 2000 idle_is '.dimmed | not'

env -u QS_CONFIG_PATH qs -p "$repo/dev/idle-inhibitor.qml" >/dev/null 2>&1 &
inhibitor=$!
cleanup() { kill "$inhibitor" 2>/dev/null; }
shown() { niri msg -j windows | jq -e 'any(.[]; .title == "idle-inhibitor")' >/dev/null; }
until_ok 5000 shown
before=$(idle_state | jq .monitorsOff)
timeout 0.5 qs ipc call idle times 4 5 6 >/dev/null
sleep 10
echo "     after 10 s held: $(idle_state | jq -c '{dimmed, monitorsOff}')"
check "with an inhibitor held, nothing dims in 10 s" idle_is '.dimmed | not'
check "nothing locks" bash -c "! timeout 0.5 qs ipc call lock state | jq -e .locked >/dev/null"
check "and the monitors stay on" idle_is ".monitorsOff == $before"

exit $((fails > 0))
}
