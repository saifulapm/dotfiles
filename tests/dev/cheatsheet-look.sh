#!/usr/bin/env bash
# The cheat sheet speaks in the one design's list voice: a Keys pill, a solid rule and a legend of lower-case key chips.
{
source "$(dirname "$0")/lib.sh"

sheet_state() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
state_is() { sheet_state | jq -e "$@" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_sheet() { niri msg action spawn -- dots-call cheatsheet toggle; until_ok 3000 state_is '.open and .settled and .rowKeys != null and (.rowKeys | length) == .rows'; }
close_sheet() { wtype -k Escape; until_ok 2000 state_is '.open == false and .drawing == false'; }
# Pixels of geometry $1 within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}

until_ok 5000 shell_status >/dev/null

open_sheet
check "the legend reads in lower-case chips ($(sheet_state | jq -c .legend))" state_is '.legend | contains("j/k move")'
check "the legend is not tracked ($(sheet_state | jq -c .legendSpacing))" state_is '.legendSpacing <= 1'
check "the heading is the pill reading Keys ($(sheet_state | jq -c .heading))" state_is '.heading == "Keys"'
# The rule under the heading is solid in the scheme's line colour #D0D7DE, so it covers a whole 300 px strip.
solid=$(near "$(sheet_state | jq -r '.ruleBox | "\(.x + 40 | floor),\(.y | floor) 300x1"')" 208 215 222 6)
check "the rule under the heading is solid in the line colour ($solid of 300 px)" test "$solid" -ge 290
close_sheet

exit $((fails > 0))
}
