#!/usr/bin/env bash
# Frost draws Artboard's layout in its own dark colours: Control's and the launcher's lit row is opaque #475666, the launcher names in Inter, and the lit name reads at 4.5:1 or more against the fill drawn behind it; Artboard keeps its #EEF1FF row.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
control_is() { control_state | jq -e "$1" >/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns each bind's command through niri.
open_control() { niri msg action spawn -- dots-call control toggle; until_ok 3000 control_is '.open and .keyboard and .cursorBox != null and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 control_is '.open == false and .drawing == false'; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 launcher_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 launcher_is '.open == false'; }
# The state's box $1 as a grim geometry; with $2-$5, the part of it at x and y offsets $2 $3, $4 by $5 px.
geo() { jq -r --arg b "$1" --argjson dx "${2:-0}" --argjson dy "${3:-0}" --argjson w "${4:-0}" --argjson h "${5:-0}" '.[$b] | "\(.x + $dx | floor),\(.y + $dy | floor) \(if $w > 0 then $w else .w | floor end)x\(if $h > 0 then $h else .h | floor end)"'; }
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
# The WCAG contrast of the text drawn in geometry $1 against the fill behind it: the fill is the box's commonest colour, the text its tenth most distant pixel, so a stray pixel cannot pass it.
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
    const f = lum(fillAt);
    const ratios = [];
    for (let i = 0; i < n; i++) { const l = lum(i); ratios.push((Math.max(l, f) + 0.05) / (Math.min(l, f) + 0.05)); }
    ratios.sort((a, z) => z - a);
    console.log((ratios[9] ?? 1).toFixed(2), "#" + fillKey.toString(16).padStart(6, "0"));
  '
}

until_ok 5000 shell_status >/dev/null

in_theme frost
open_control
check "frost: Control's cursor row's fill is #475666 ($(control_state | jq -c .cursorFill))" control_is '.cursorFill == "#475666"'
row=$(near "$(control_state | geo cursorBox 60 4 200 8)" 71 86 102 3)
check "frost: Control's cursor row draws #475666 across its width ($row of 1600 px)" test "$row" -gt 1200
close_control

open_launcher
wtype fo
until_ok 3000 launcher_is '.query == "fo" and .cursorName != null'
check "frost: the launcher names its rows in Inter ($(launcher_state | jq -c .nameFont))" launcher_is '.nameFont == "Inter"'
check "frost: the launcher's cursor row's fill is #475666 ($(launcher_state | jq -c .cursorFill))" launcher_is '.cursorFill == "#475666"'
read -r ratio fill < <(drawn_contrast "$(launcher_state | geo cursorNameBox)")
check "frost: the lit row's name reads at 4.5:1 or more against the fill drawn behind it ($ratio on $fill)" node -e 'process.exit(+process.argv[1] >= 4.5 ? 0 : 1)' "$ratio"
check "frost: that fill is the lit row's #475666 ($fill)" test "$fill" = "#475666"
close_launcher

in_theme artboard
open_control
check "artboard: Control's cursor row's fill is still #EEF1FF ($(control_state | jq -c .cursorFill))" control_is '.cursorFill == "#eef1ff"'
row=$(near "$(control_state | geo cursorBox 60 4 200 8)" 238 241 255 3)
check "artboard: Control's cursor row draws #EEF1FF across its width ($row of 1600 px)" test "$row" -gt 1200
close_control

in_theme paper
exit $((fails > 0))
}
