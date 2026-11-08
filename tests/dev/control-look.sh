#!/usr/bin/env bash
# Control draws in the one design's list voice: a tint pill tab, a tinted rounded row with the detail under the name, no rule and lower-case key chips.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_control() { niri msg action spawn -- dots-call control toggle; until_ok 3000 state_is '.open and .keyboard and .cursorBox != null and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 state_is '.open == false and .drawing == false'; }
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
# A geometry inside the state's box $1: x offset, y offset, width and height; a negative offset counts from the far edge.
box_geo() {
  control_state | jq -r --arg b "$1" --argjson dx "$2" --argjson dy "$3" --argjson w "$4" --argjson h "$5" \
    '.[$b] | "\((if $dx < 0 then .x + .w + $dx else .x + $dx end) | floor),\((if $dy < 0 then .y + .h + $dy else .y + $dy end) | floor) \($w)x\($h)"'
}

until_ok 5000 shell_status >/dev/null

open_control
check "the current tab is the accent's veil #243249ce reading Audio ($(control_state | jq -c '[.tabFill, .tabText]'))" state_is '.tabFill == "#243249ce" and .tabText == "Audio"'
check "the section hint reads as written ($(control_state | jq -c .hint))" state_is '.hint == "h/l volume · ↵ default or move · m mute · p profile · r port"'
pill=$(near "$(box_geo tabBox 2 6 6 8)" 203 208 230 4)
check "the current tab draws the veil over the card's paper ($pill of 48 px)" test "$pill" -eq 48
pill_corner=$(near "$(box_geo tabBox 0 0 2 2)" 228 230 234 4)
check "the tab pill's corner reads the card's paper, so it is rounded ($pill_corner of 4 px)" test "$pill_corner" -ge 3
check "the cursor row's fill is the accent's veil #243249ce ($(control_state | jq -c .cursorFill))" state_is '.cursorFill == "#243249ce"'
tint=$(near "$(box_geo cursorBox -70 4 8 8)" 203 208 230 4)
check "inside the cursor row reads the veil over the card's paper ($tint of 64 px)" test "$tint" -eq 64
corner=$(near "$(box_geo cursorBox 0 0 2 2)" 228 230 234 4)
check "the cursor row's corner reads the card's paper, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
check "the legend keys are lower-case chips ($(control_state | jq -c .legend))" state_is '.legend == "tab section  j/k move  esc close" and .legendDrawn == .legend'
# No rule runs under the heading: its 1 px slot reads the card's paper across a whole 300 px strip.
rule=$(near "$(box_geo ruleBox 20 0 300 1)" 228 230 234 4)
check "no rule runs under the heading ($rule of 300 px read the card's paper)" test "$rule" -ge 290
close_control

exit $((fails > 0))
}
