#!/usr/bin/env bash
# The passage turns over at local midnight on the clock's tick, reading deen once, and a deen that hangs is ended at a later tick; the shell runs in a zone whose midnight is about a minute and a half away.
{
source "$(dirname "$0")/lib-midnight.sh" 80

until_ok 5000 passage_is --arg d "$before" '.date == $d and (.bn != "" or .en != "")'
check "before midnight the passage is $before's ($(passage | jq -c '[.date, .kind, .ref]'), zone $DOTS_DEV_TZ)" passage_is --arg d "$before" '.date == $d'
check "the clock's is the one Tick running ($(shell_status | jq .timers))" sh -c "[ \$(timeout 0.5 qs ipc call shell status | jq .timers) = 1 ]"

n=$(reads)
until_midnight -2
check "a tick on the same date reads deen no more ($n then $(reads))" test "$(reads)" = "$n"
until_midnight 3
until_ok 5000 passage_is --arg d "$after" '.date == $d and (.bn != "" or .en != "")'
check "by the tick at midnight the passage is $after's ($(passage | jq -c '[.date, .kind, .ref]'))" passage_is --arg d "$after" '.date == $d and (.bn != "" or .en != "")'
check "read from deen once ($n then $(reads))" test "$(reads)" = $((n + 1))
check "the margins read the same date ($(margins_date))" test "$(margins_date)" = "$(TZ=$DOTS_DEV_TZ date -d "@$midnight" '+%a %-d %b')"
check "a cut: the first sheet draws the new day ($(passage | jq -c '.drawn | map(length)'))" passage_is --arg d "$after" '(.drawn | length) == 1 and (.drawn[0] | length) == 1 and .drawn[0][0].bn == .bn and .drawn[0][0].en == .en'

# A hadith day whose deen never answers draws its fallback once a tick finds the read 30 s old.
echo hang >"$work/mode"
n=$(reads)
dots-call passage date 2026-11-08
until_midnight 62
until_ok 5000 passage_is '.date == "2026-11-08" and (.bn != "" or .en != "")'
check "a hanging deen ends at the tick and 2026-11-08 falls back ($(passage | jq -c '[.fallback, .ref]'))" passage_is '.date == "2026-11-08" and .fallback == true and .ref == "Ralph Waldo Emerson"'
check "with no second read stacked on it ($n then $(reads))" test "$(reads)" = $((n + 1))

exit $((fails > 0))
}
