#!/usr/bin/env bash
# Each theme's notification centre draws in the launcher's voice: Paper's ink row and red marker, Artboard's tinted rounded cursor, Blueprint's header line, dashed rule and cyan cursor.
{
source "$(dirname "$0")/lib.sh"

notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
state_is() { notifs | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_centre() { niri msg action spawn -- qs ipc call notifs toggle; until_ok 3000 state_is '.open and .cursorBox != null'; }
close_centre() { niri msg action spawn -- qs ipc call notifs toggle; until_ok 2000 state_is '.open == false'; }
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
  notifs | jq -r --arg b "$1" --argjson dx "$2" --argjson dy "$3" --argjson w "$4" --argjson h "$5" \
    '.[$b] | "\((if $dx < 0 then .x + .w + $dx else .x + $dx end) | floor),\((if $dy < 0 then .y + .h + $dy else .y + $dy end) | floor) \($w)x\($h)"'
}

until_ok 5000 shell_status >/dev/null
notify-send -a mail "mail 1" "a body line"
notify-send -a chat "chat 1"
until_ok 2000 state_is '.count == 2'

in_theme paper
open_centre
check "paper: the heading is the ink chip reading NOTIFICATIONS ($(notifs | jq -c '[.headingKind, .heading]'))" state_is '.headingKind == "chip" and .heading == "NOTIFICATIONS"'
check "paper: the cursor row's fill is ink ($(notifs | jq -c .cursorFill))" state_is '.cursorFill == "#1c1915"'
row_ink=$(near "$(box_geo cursorBox 60 2 200 4)" 28 25 21 6)
check "paper: the cursor row draws ink across its width ($row_ink of 800 px)" test "$row_ink" -gt 700
marker=$(near "$(box_geo cursorBox 0 4 50 30)" 200 56 30 40)
check "paper: the cursor row's ▸ marker is #C8381E ($marker px)" test "$marker" -gt 3 -a "$marker" -lt 200
check "paper: the legend is tracked caps with ⇧D for clear all ($(notifs | jq -c '[.legend, .legendSpacing]'))" state_is '.legend == "J/K MOVE  ↵ OPEN  D DISMISS  ⇧D CLEAR ALL  / SEARCH  ESC CLOSE" and .legendSpacing > 1'
close_centre

in_theme artboard
open_centre
check "artboard: the heading is the pill reading Notifications ($(notifs | jq -c '[.headingKind, .heading]'))" state_is '.headingKind == "pill" and .heading == "Notifications"'
check "artboard: the cursor row's fill is #EEF1FF ($(notifs | jq -c .cursorFill))" state_is '.cursorFill == "#eef1ff"'
tint=$(near "$(box_geo cursorBox 300 2 8 4)" 238 241 255 3)
check "artboard: inside the cursor row reads the tint ($tint of 32 px)" test "$tint" -eq 32
corner=$(near "$(box_geo cursorBox 0 0 2 2)" 255 255 255 3)
check "artboard: the cursor row's corner reads the card's white, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
close_centre

in_theme blueprint
open_centre
check "blueprint: the header line reads NOTIFICATIONS ($(notifs | jq -c '[.headingKind, .heading]'))" state_is '.headingKind == "header" and .heading == "NOTIFICATIONS"'
check "blueprint: the rule sits under the header line" state_is '.ruleBox.y > .headingBox.y'
# Dashes of 4 px leave gaps of 3 that read the card's #0A1526; a solid rule leaves none, wherever its fractional y blends it.
gaps=$(near "$(box_geo ruleBox 20 0 280 1)" 10 21 38 6)
check "blueprint: the rule under the header is dashed ($gaps of 280 px read the card between dashes)" test "$gaps" -gt 60 -a "$gaps" -lt 200
check "blueprint: the cursor row's fill is #7FE3F0 ($(notifs | jq -c .cursorFill))" state_is '.cursorFill == "#7fe3f0"'
cyan=$(near "$(box_geo cursorBox 300 2 8 4)" 127 227 240 3)
check "blueprint: inside the cursor row reads the accent ($cyan of 32 px)" test "$cyan" -eq 32
check "blueprint: every legend key is bracketed ($(notifs | jq -c .legendKeys))" state_is '.legendKeys == ["[J/K]", "[↵]", "[D]", "[⇧D]", "[/]", "[ESC]"]'
close_centre

in_theme paper
exit $((fails > 0))
}
