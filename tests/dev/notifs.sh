#!/usr/bin/env bash
# The notification history: 200 entries kept across restarts, and Do Not Disturb.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
count() { notifs | jq .count; }

for i in $(seq 1 201); do notify-send "n $i"; done
until_ok 2000 eval '[ "$(count)" = 200 ]'
state=$(notifs)
holds() { jq -e "$1" <<<"$state" >/dev/null; }
check "after 201 notifications the history holds 200" holds '.count == 200'
check "the newest is n 201 and the oldest kept is n 2" holds '.summaries[0] == "n 201" and .summaries[-1] == "n 2"'

timeout 0.5 qs ipc call notifs dnd true
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
check "the history and Do Not Disturb survive a shell restart" eval 'notifs | jq -e ".count == 200 and .dnd" >/dev/null'

notify-send dnd-hi
sleep 0.5
check "with Do Not Disturb on the island stays at rest" eval 'island | jq -e ".mode == \"rest\"" >/dev/null'
check "with Do Not Disturb on the notification still reaches the history" eval 'notifs | jq -e ".summaries[0] == \"dnd-hi\"" >/dev/null'
timeout 0.5 qs ipc call notifs dnd false

start=$(now_ms)
for i in $(seq 1 20); do notify-send "burst $i"; done
sent=$(($(now_ms) - start))
until_ok 1000 eval 'notifs | jq -e ".summaries[0] == \"burst 20\"" >/dev/null'
check "the 20 went out within 1 s (${sent} ms)" test "$sent" -le 1000
check "20 notifications sent in ${sent} ms all reach the history" eval 'notifs | jq -e "[.summaries[0:20][] | select(startswith(\"burst \"))] | length == 20" >/dev/null'
check "the island ends showing the 20th" eval 'island | jq -e ".text | test(\"burst 20$\")" >/dev/null'

exit $((fails > 0))
}
