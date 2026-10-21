#!/usr/bin/env bash
# An agent's lease: lock unlock ends the lock without the password, renew extends it to at most 2 hours, and its end or any lock relocks.
{
source "$(dirname "$0")/lib.sh"

marker=$XDG_STATE_HOME/dots/locked
shell_pid() { systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT"; }
# The pid picks the instance, since a killed one's socket lingers.
call() { timeout 0.5 env -u QS_CONFIG_PATH qs ipc --pid "$(shell_pid)" call "$@" 2>/dev/null; }
lock_state() { call lock state; }
state_is() { lock_state | jq -e "$1" >/dev/null 2>&1; }
locked_shown() { state_is '.locked and .secure'; }
lock_now() { niri msg action spawn -- dots-call lock lock; }
journal() { journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat 2>/dev/null; }

until_ok 5000 shell_status >/dev/null
check "unlocked at start, with no lease" state_is '.locked == false and .heldBy == "" and .leaseUntil == 0'
check "an unlock while unlocked answers an error and starts no lease" bash -c "$(declare -f call shell_pid); DOTS_DEV_UNIT=$DOTS_DEV_UNIT; call lock unlock claude 1 | jq -e '.error' >/dev/null && call lock state | jq -e '.heldBy == \"\"' >/dev/null"

lock_now
until_ok 3000 locked_shown
check "it locks" locked_shown

t0=$(now_ms)
reply=$("$repo/bin/dots-call" lock unlock claude 1)
check "dots-call lock unlock answers the state ($reply)" jq -e '.locked == false and .heldBy == "claude"' <<<"$reply"
check "the lease holds for claude, ending 60 s from now" state_is ".locked == false and .heldBy == \"claude\" and (.leaseUntil - $t0) >= 59000 and (.leaseUntil - $t0) <= 61000"
check "the marker keeps the lease, so a killed shell relocks" grep -q '^lease claude until ' "$marker"
until_ok 2000 state_is '.monitorsOff == 1'
check "an agent unlock asks niri to turn the monitors off ($(lock_state | jq .monitorsOff) times)" state_is '.monitorsOff == 1'
phone=$DOTS_DEV_DIR/phone.jsonl
until_ok 2000 test -s "$phone"
check "the lease's start tells the phone once, naming claude ($(cat "$phone" 2>/dev/null))" bash -c "[ \$(wc -l <'$phone') = 1 ] && jq -e '.title | test(\"claude\")' '$phone' >/dev/null"
check "the journal holds the unlock" bash -c "journalctl --user -u $DOTS_DEV_UNIT --no-pager -o cat | grep -qF 'lock: agent unlock by claude for 1 min'"

call lock renew claude 200 >/dev/null
check "renew claude 200 ends the lease 120 min after the unlock ($(lock_state | jq -c '{unlockedAt, leaseUntil}'))" state_is '.leaseUntil == .unlockedAt + 7200000'
call lock renew claude 1 >/dev/null
check "renew claude 1 brings it back to a minute from now" state_is ".leaseUntil - $(now_ms) <= 60000 and .leaseUntil - $(now_ms) >= 58000"
check "a renew tells the phone nothing" test "$(wc -l <"$phone")" = 1

# The lease's end relocks; a Tick checks once a second.
ends=$(lock_state | jq .leaseUntil)
until_ok $((ends - $(now_ms) + 3000)) locked_shown
late=$(($(now_ms) - ends))
check "the lease's end locks within 2 s ($late ms late)" test "$late" -le 2000
check "and ends the lease" state_is '.heldBy == "" and .leaseUntil == 0'
check "and the marker holds the lock's time" grep -qE '^[0-9]{4}-' "$marker"
check "renew without a lease answers an error" bash -c "$(declare -f call shell_pid); DOTS_DEV_UNIT=$DOTS_DEV_UNIT; call lock renew claude 5 | jq -e '.error' >/dev/null"

# A lock right after an unlock must leave its marker (the 4c13c1d race).
call lock unlock claude 5 >/dev/null
call lock lock >/dev/null
sleep 0.3
check "a lock right after an unlock leaves the marker in place" grep -qE '^[0-9]{4}-' "$marker"
check "and ends the lease" state_is '.locked and .heldBy == ""'

# A shell killed mid-lease comes back locked, not unlocked with no lease.
until_ok 3000 locked_shown
call lock unlock claude 5 >/dev/null
until_ok 1000 state_is '.locked == false'
old=$(shell_pid)
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
restarted_locked() { [ "$(shell_pid)" != "$old" ] && [ "$(shell_pid)" != 0 ] && locked_shown; }
until_ok 5000 restarted_locked
check "a shell killed mid-lease restarts locked" restarted_locked
check "with no lease" state_is '.heldBy == ""'

# A holder's name is anyone's text: one line, no bidi controls.
call lock unlock "$(printf 'cl\naude‮ x')" 5 >/dev/null
check "a name with a newline and U+202E holds as one line ($(lock_state | jq -c .heldBy))" state_is '.heldBy == "cl aude x"'
call lock lock >/dev/null
until_ok 3000 locked_shown
call lock unlock "$(printf 'x%.0s' {1..200})" 5 >/dev/null
check "a 200-character name holds whole" state_is '(.heldBy | length) == 200'
call lock lock >/dev/null
until_ok 3000 locked_shown

# A password still in PAM when an agent unlocks: its late success must not empty the lease's marker, or a killed shell would restart unlocked.
slow=$DOTS_DEV_DIR/pam-slow
printf '#!/usr/bin/env bash\nsleep 2\nexec %q\n' "$repo/dev/pam-test-password" >"$slow"
chmod +x "$slow"
cp "$DOTS_PAM_DIR/dots-lock" "$DOTS_DEV_DIR/dots-lock.fast"
sed -i "s|$repo/dev/pam-test-password|$slow|" "$DOTS_PAM_DIR/dots-lock"
wtype dots-test-pass
wtype -k Return
sleep 0.3
call lock unlock claude 5 >/dev/null
sleep 2.5
check "a password that passes after an agent unlock leaves the lease's marker ($(head -c 40 "$marker"))" grep -q '^lease claude until ' "$marker"
check "and the lease" state_is '.locked == false and .heldBy == "claude"'
cp "$DOTS_DEV_DIR/dots-lock.fast" "$DOTS_PAM_DIR/dots-lock"
call lock lock >/dev/null
until_ok 3000 locked_shown

wtype dots-test-pass
wtype -k Return
until_ok 3000 state_is '.locked == false'
check "the test password still unlocks, with no lease" state_is '.locked == false and .heldBy == ""'

exit $((fails > 0))
}
