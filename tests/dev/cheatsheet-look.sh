#!/usr/bin/env bash
# The cheat sheet speaks in its theme's list voice: Paper's tracked caps legend, Blueprint's bracketed keys under a KEYS header line and a dashed rule.
{
source "$(dirname "$0")/lib.sh"

sheet_state() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
state_is() { sheet_state | jq -e "$@" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_sheet() { niri msg action spawn -- qs ipc call cheatsheet toggle; until_ok 3000 state_is '.open and .settled and .rowKeys != null and (.rowKeys | length) == .rows'; }
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

in_theme paper
open_sheet
check "paper: the legend reads in caps ($(sheet_state | jq -c .legend))" state_is '.legend | contains("J/K MOVE")'
check "paper: the legend is tracked ($(sheet_state | jq -c .legendSpacing))" state_is '.legendSpacing > 1'
close_sheet

in_theme blueprint
open_sheet
check "blueprint: every row key is bracketed ($(sheet_state | jq -c '.rowKeys[0:3]'))" state_is '(.rowKeys | length) == .rows and .rows > 0 and all(.rowKeys[]; test("^\\[.*\\]$"))'
check "blueprint: every legend key is bracketed ($(sheet_state | jq -c .legendKeys))" state_is '(.legendKeys | length) == 5 and all(.legendKeys[]; test("^\\[.*\\]$"))'
check "blueprint: the heading reads KEYS on the header line ($(sheet_state | jq -c '[.heading, .headingKind]'))" state_is '.heading == "KEYS" and .headingKind == "header"'
# A 4-on 3-off dash covers about 57 % of a 300 px strip along the rule; a solid rule covers all of it.
dash=$(near "$(sheet_state | jq -r '.ruleBox | "\(.x + 40 | floor),\(.y | floor) 300x1"')" 46 90 114 24)
check "blueprint: the rule under the heading is dashed in #2E5A72 ($dash of 300 px)" test "$dash" -gt 100 -a "$dash" -lt 250
close_sheet

in_theme paper
exit $((fails > 0))
}
