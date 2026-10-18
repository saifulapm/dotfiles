#!/usr/bin/env bash
# The island as the notification server: notify-send runs on the nested session bus that lib.sh sources.
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }

notify-send hi
until_ok 2000 mode_is notification
state=$(island)
echo "     island: $state"
shows_hi() { jq -e '.text | test("hi")' <<<"$state" >/dev/null; }
check "notify-send hi shows hi in the island" shows_hi
until_ok 8000 mode_is rest
# Both ends come from the shell's own mode clock, so the poll's latency does not count.
held=$(($(island | jq .since) - $(jq .since <<<"$state")))
check "the island is back to the clock after 5.0 ± 0.3 s (${held} ms)" test "$held" -ge 4700 -a "$held" -le 5300

notify-send -u critical stop
until_ok 2000 mode_is notification
sleep 30
check "a critical notification is still shown after 30 s" eval 'island | jq -e ".mode == \"notification\" and (.text | test(\"stop\"))" >/dev/null'
status=$(shell_status)
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "a critical notification runs no timer" one_timer

start=$(now_ms)
for i in $(seq 1 20); do notify-send "seq $i"; done
echo "     20 notifications sent in $(($(now_ms) - start)) ms"
until_ok 1000 eval 'island | jq -e ".text | test(\"seq 20$\")" >/dev/null'
check "after 20 notifications in a row the island shows the 20th" eval 'island | jq -e ".text | test(\"seq 20$\")" >/dev/null'
width_ok() { island | jq -e '.width <= 560' >/dev/null; }
notify-send "$(printf 'long %.0s' $(seq 1 200))"
until_ok 1000 eval 'island | jq -e ".text | test(\"long\")" >/dev/null'
check "a long notification keeps the island within 560 px" width_ok

notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
notify-send -u critical "battery low"
until_ok 1000 eval 'island | jq -e ".text | test(\"battery low\")" >/dev/null'
notify-send "chat ping"
until_ok 1000 eval 'island | jq -e ".text | test(\"chat ping\")" >/dev/null'
critical_back() { island | jq -e '.mode == "notification" and (.text | test("battery low"))' >/dev/null; }
until_ok 7000 critical_back
check "a critical notification comes back once a newer one's 5 s are up" critical_back

id=$(notify-send -p "download 10%")
until_ok 1000 eval 'island | jq -e ".text | test(\"download 10%\")" >/dev/null'
before=$(notifs | jq .count)
notify-send -r "$id" "download 90%"
replaced() { island | jq -e '.text | test("download 90%")' >/dev/null; }
until_ok 1000 replaced
check "a notification that replaces another shows its new text" replaced
in_place() { notifs | jq -e --argjson n "$before" '.summaries[0] == "download 90%" and .count == $n and all(.summaries[]; . != "download 10%")' >/dev/null; }
check "and takes the old one's place in the history" in_place

exit $((fails > 0))
