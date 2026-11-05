#!/usr/bin/env bash
# A date set through passage date stays on the paper across local midnight, with no read at the tick; the shell runs in a zone whose midnight is about half a minute away.
{
source "$(dirname "$0")/lib-midnight.sh" 25

dots-call passage date 2026-11-03
until_ok 5000 passage_is '.date == "2026-11-03" and (.bn != "" or .en != "")'
n=$(reads)
until_midnight 3
check "the tick at midnight leaves 2026-11-03 on screen ($(passage | jq -c '[.date, .ref]'))" passage_is '.date == "2026-11-03" and .ref == "সূরা আশ-শারহ ৯৪:৬" and .fallback == false'
# The lock's passage follows no pinned date, so its own turn over is the one read midnight takes.
check "and reads deen only for the lock's new day ($n then $(reads))" test "$(reads)" = "$((n + 1))"
dots-call passage date ""
until_ok 5000 passage_is --arg d "$after" '.date == $d and (.bn != "" or .en != "")'
check "back to today it is $after's, the date the clock turned to ($(passage | jq -c '[.date, .ref]'))" passage_is --arg d "$after" '.date == $d'

exit $((fails > 0))
}
