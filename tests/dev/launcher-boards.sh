#!/usr/bin/env bash
# Each launcher mode draws its board 3 form in the island: the calculator's 40 px answer, a reminder's one tile.
{
source "$(dirname "$0")/lib.sh"

launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }

until_ok 5000 shell_status >/dev/null

open_launcher
wtype "= 2+2"
until_ok 3000 state_is '.answer.text == "4"'
check "= 2+2 draws the Calculator chip and 4 at 40 px bold with 2+2 under it ($(launcher | jq -c '{chip: .chip.name, answer, kinds}'))" state_is '.chip.name == "Calculator" and .answer == {text: "4", size: 40, bold: true, under: "2+2"} and .kinds == ["answer"] and .rowHeights == [80] and .filled == [false]'
wtype -k Return
until_ok 2000 state_is '.open == false'
copied() { [ "$(wl-paste -n 2>/dev/null)" = 4 ]; }
until_ok 2000 copied
check "Enter puts 4 on the clipboard ($(wl-paste -n 2>/dev/null))" copied

open_launcher
wtype "r 1m tea"
until_ok 3000 state_is '.results[0] == "tea"'
check "r 1m tea draws one 56 px filled tile reading tea with the time it rings ($(launcher | jq -c '{kinds, results, notes, rowHeights, filled}'))" state_is '.kinds[0] == "tile" and .results[0] == "tea" and (.notes[0] | test("[0-9]{2}:[0-9]{2}")) and .rowHeights[0] == 56 and .filled[0] == true and ([.kinds[] | select(. == "tile")] | length) == 1'
close_launcher
exit "$fails"
}
