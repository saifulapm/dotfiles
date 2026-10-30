#!/usr/bin/env bash
# A date set through passage date stays on the paper across local midnight, with no read at the tick; the shell runs in a zone whose midnight is about half a minute away.
{
source "$(dirname "$0")/lib-midnight.sh" 25

dots-call passage date 2026-11-04
until_ok 5000 passage_is '.date == "2026-11-04" and .en != ""'
n=$(reads)
until_midnight 3
check "the tick at midnight leaves 2026-11-04 on screen ($(passage | jq -c '[.date, .ref]'))" passage_is '.date == "2026-11-04" and .en != "" and .fallback == false'
check "and reads deen no more ($n then $(reads))" test "$(reads)" = "$n"
dots-call passage date ""
until_ok 5000 passage_is --arg d "$after" '.date == $d and .en != ""'
check "back to today it is $after's, the date the clock turned to ($(passage | jq -c '[.date, .ref]'))" passage_is --arg d "$after" '.date == $d'

exit $((fails > 0))
}
