#!/usr/bin/env bash
# Goals' warnings, the selected goal's due date and the delete confirm, are danger text in Paper; Frost's danger is a dot only, so there they are ink after a 6 px danger dot and read at 4.5:1 or more.
{
source "$(dirname "$0")/lib.sh"

goals_state() { timeout 0.5 qs ipc call goals state 2>/dev/null; }
state_is() { goals_state | jq -e "$@" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { legacy_theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
open_goals() {
  until_ok 10000 desk_up
  niri msg action spawn -- dots-call goals toggle
  until_ok 3000 state_is '.open and .keyboard and .settled'
}
close_goals() { wtype -k Escape; until_ok 2000 state_is '.open == false and .drawing == false'; }
answer() {
  until_ok 2000 state_is --arg k "$1" '.prompt.kind == $k' || return 1
  [ -n "$2" ] && wtype "$2"
  until_ok 2000 state_is --arg t "$2" '.prompt.text == $t' || return 1
  wtype -k Return
}
geo() { goals_state | jq -r "$1"' | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h | ceil)"'; }
# How many pixels of geometry $1 lie within $5 of r g b.
near() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
# The 10th highest contrast in geometry $1 against its commonest colour, and that colour: the text against the fill drawn behind it.
drawn_contrast() {
  grim -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length), n = head[1] * head[2];
    const lum = (i) => [0, 1, 2].map((c) => px[i * 3 + c] / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)).reduce((s, v, c) => s + v * [0.2126, 0.7152, 0.0722][c], 0);
    const counts = new Map();
    for (let i = 0; i < n; i++) { const k = px.readUIntBE(i * 3, 3); counts.set(k, (counts.get(k) ?? 0) + 1); }
    const fillKey = [...counts].sort((a, z) => z[1] - a[1])[0][0];
    let fillAt = 0;
    while (px.readUIntBE(fillAt * 3, 3) !== fillKey) fillAt++;
    const f = lum(fillAt), ratios = [];
    for (let i = 0; i < n; i++) { const l = lum(i); ratios.push((Math.max(l, f) + 0.05) / (Math.min(l, f) + 0.05)); }
    ratios.sort((a, z) => z - a);
    console.log((ratios[9] ?? 1).toFixed(2), "#" + fillKey.toString(16).padStart(6, "0"));
  '
}

until_ok 5000 shell_status >/dev/null
open_goals
wtype n
answer title "Ship v2"
answer deadline 3d
until_ok 2000 state_is '.active == ["Ship v2"] and .prompt == null'
close_goals

in_theme frost
open_goals
until_ok 2000 state_is '.due != null'
echo "     due: $(goals_state | jq -c .due)"
check "frost: the selected goal's due date is ink #d8dee9 after a dot ($(goals_state | jq -c '[.due.text, .due.color, .due.dot]'))" state_is '.due.color == "#d8dee9" and .due.dot.w == 6 and .due.dot.x < .due.box.x'
dot=$(near "$(geo .due.dot)" 191 97 106 24)
check "frost: the due date's dot draws danger #bf616a ($dot of 36 px)" test "$dot" -ge 12
read -r ratio fill < <(drawn_contrast "$(geo .due.box)")
check "frost: the due date reads at 4.5:1 or more against the fill drawn behind it ($ratio on $fill)" node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$ratio"
# Within 14, since the ink's subpixel fringes reach 167 121 95.
red=$(near "$(geo .due.box)" 191 97 106 14)
check "frost: no pixel of the due date draws danger red ($red px)" test "$red" -eq 0
wtype d
until_ok 2000 state_is '.confirm and .confirmLabel != null'
check "frost: delete? y is ink #d8dee9 after a dot ($(goals_state | jq -c .confirmLabel))" state_is '.confirmLabel.text == "delete? y" and .confirmLabel.color == "#d8dee9" and .confirmLabel.dot.w == 6'
dot=$(near "$(geo .confirmLabel.dot)" 191 97 106 24)
check "frost: the confirm's dot draws danger #bf616a ($dot of 36 px)" test "$dot" -ge 12
wtype n
until_ok 2000 state_is '.confirm == false'
close_goals

in_theme paper
open_goals
until_ok 2000 state_is '.due != null'
check "paper: the selected goal's due date is Paper's danger #c8381e with no dot ($(goals_state | jq -c '[.due.color, .due.dot]'))" state_is '.due.color == "#c8381e" and .due.dot == null'
red=$(near "$(geo .due.box)" 200 56 30 40)
check "paper: the due date draws vermilion pixels ($red px)" test "$red" -gt 4
wtype d
until_ok 2000 state_is '.confirm and .confirmLabel != null'
check "paper: delete? y is danger with no dot ($(goals_state | jq -c .confirmLabel))" state_is '.confirmLabel.color == "#c8381e" and .confirmLabel.dot == null'
wtype n
close_goals

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0))
}
