#!/usr/bin/env bash
# Control draws in its theme's list voice: Paper's ink row and caps legend, Artboard's tint pill and rounded row, Blueprint's header, dashed rule, cyan row and bracketed keys.
{
source "$(dirname "$0")/lib.sh"

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_control() { niri msg action spawn -- qs ipc call control toggle; until_ok 3000 state_is '.open and .keyboard and .cursorBox != null and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 state_is '.open == false and .drawing == false'; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
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

in_theme paper
open_control
check "paper: the cursor row's fill is ink ($(control_state | jq -c .cursorFill))" state_is '.cursorFill == "#1c1915"'
row_ink=$(near "$(box_geo cursorBox 60 4 200 8)" 28 25 21 6)
check "paper: the cursor row draws ink across its width ($row_ink of 1600 px)" test "$row_ink" -gt 1200
marker=$(near "$(box_geo cursorBox 0 4 50 30)" 200 56 30 40)
check "paper: the cursor row's ▸ marker is #C8381E ($marker px)" test "$marker" -gt 6 -a "$marker" -lt 200
check "paper: the legend is tracked caps ($(control_state | jq -c .legend))" state_is '.legend == "TAB SECTION  J/K MOVE  ESC CLOSE" and .legendSpacing > 1'
check "paper: the section hint reads in caps ($(control_state | jq -c .hint))" state_is '.hint == "H/L VOLUME · ↵ DEFAULT · M MUTE"'
close_control

in_theme artboard
open_control
check "artboard: the current tab is the #EEF1FF pill reading Audio ($(control_state | jq -c '[.tabFill, .tabText]'))" state_is '.tabFill == "#eef1ff" and .tabText == "Audio"'
check "artboard: the section hint reads as written, not in caps ($(control_state | jq -c .hint))" state_is '.hint == "h/l volume · ↵ default · m mute"'
pill=$(near "$(box_geo tabBox 2 6 6 8)" 238 241 255 3)
check "artboard: the current tab draws the tint ($pill of 48 px)" test "$pill" -eq 48
pill_corner=$(near "$(box_geo tabBox 0 0 2 2)" 255 255 255 3)
check "artboard: the tab pill's corner reads the card's white, so it is rounded ($pill_corner of 4 px)" test "$pill_corner" -ge 3
check "artboard: the cursor row's fill is #EEF1FF ($(control_state | jq -c .cursorFill))" state_is '.cursorFill == "#eef1ff"'
tint=$(near "$(box_geo cursorBox -70 4 8 8)" 238 241 255 3)
check "artboard: inside the cursor row reads the tint ($tint of 64 px)" test "$tint" -eq 64
corner=$(near "$(box_geo cursorBox 0 0 2 2)" 255 255 255 3)
check "artboard: the cursor row's corner reads the card's white, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
close_control

in_theme blueprint
open_control
check "blueprint: the header reads CONTROL // AUDIO ($(control_state | jq -c .heading))" state_is '.heading == "CONTROL // AUDIO"'
# A dashed rule draws the line colour on part of its row, its antialiased dash ends included; a solid one on all of it.
rule=$(near "$(box_geo ruleBox 0 0 600 1)" 46 90 114 12)
check "blueprint: the rule under the header is dashed ($rule of 600 px in #2E5A72)" test "$rule" -gt 250 -a "$rule" -lt 540
check "blueprint: the current tab takes the cyan cursor colours ($(control_state | jq -c .tabFill))" state_is '.tabFill == "#7fe3f0"'
check "blueprint: the cursor row's fill is #7FE3F0 ($(control_state | jq -c .cursorFill))" state_is '.cursorFill == "#7fe3f0"'
cyan=$(near "$(box_geo cursorBox -60 3 8 8)" 127 227 240 3)
check "blueprint: inside the cursor row reads the accent ($cyan of 64 px)" test "$cyan" -eq 64
check "blueprint: the legend's keys are bracketed ($(control_state | jq -c .legend))" state_is '.legend == "[TAB] SECTION  [J/K] MOVE  [ESC] CLOSE"'
close_control

in_theme paper
exit $((fails > 0))
}
