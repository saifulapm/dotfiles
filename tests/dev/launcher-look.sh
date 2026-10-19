#!/usr/bin/env bash
# Each theme's launcher looks like its board: Paper's ink row, Artboard's icon tiles and tinted cursor, Blueprint's header, numbers and cyan cursor.
{
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_launcher() { niri msg action spawn -- qs ipc call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
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
# A geometry inside the cursor row's box: x offset, y offset, width and height; a negative offset counts from the far edge.
cursor_geo() {
  launcher_state | jq -r --argjson dx "$1" --argjson dy "$2" --argjson w "$3" --argjson h "$4" \
    '.cursorBox | "\((if $dx < 0 then .x + .w + $dx else .x + $dx end) | floor),\((if $dy < 0 then .y + .h + $dy else .y + $dy end) | floor) \($w)x\($h)"'
}

# An app whose icon no theme has, written after the shell's scan, so the scan must pick it up.
mkdir -p "$DOTS_DEV_DIR/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Zz Iconless\nIcon=dots-no-such-icon\nExec=true\n' >"$DOTS_DEV_DIR/data/applications/dots-iconless.desktop"
long="Zz Long $(printf 'name%.0s' {1..48})"
printf '[Desktop Entry]\nType=Application\nName=%s\nGenericName=Long Detail\nExec=true\n' "$long" >"$DOTS_DEV_DIR/data/applications/dots-long.desktop"

until_ok 5000 shell_status >/dev/null

in_theme paper
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .cursorBox != null'
check "paper: the cursor row's fill is ink ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#1c1915"'
check "paper: the query is Instrument Serif at 34 px and the detail italic Instrument Serif at 16 px" state_is '.queryFont == ["Instrument Serif", 34] and .detailFont == ["Instrument Serif", 16, true]'
row_ink=$(near "$(cursor_geo 60 4 200 8)" 28 25 21 6)
check "paper: the cursor row draws ink across its width ($row_ink of 1600 px)" test "$row_ink" -gt 1200
marker=$(near "$(cursor_geo 0 4 50 30)" 200 56 30 40)
check "paper: the cursor row's ▸ marker is #C8381E ($marker px)" test "$marker" -gt 6 -a "$marker" -lt 200
close_launcher

in_theme artboard
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .results[0] == "Foot" and .cursorBox != null'
check "artboard: the cursor row's fill is #EEF1FF ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#eef1ff"'
tint=$(near "$(cursor_geo -70 4 8 8)" 238 241 255 3)
check "artboard: inside the cursor row reads the tint ($tint of 64 px)" test "$tint" -eq 64
corner=$(near "$(cursor_geo 0 0 2 2)" 255 255 255 3)
check "artboard: the cursor row's corner reads the card's white, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
check "artboard: Foot's row draws its icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] | test("^image://icon/foot")'
# foot's icon is a dark terminal, so its tile holds dark pixels that the tint never has.
dark=$(near "$(cursor_geo 12 12 32 32)" 30 30 30 40)
check "artboard: Foot's 32 px icon shows in its slot ($dark dark px)" test "$dark" -gt 100
check "artboard: the mode pill reads Apps and the footer shows five prefix chips" state_is '.label == "Apps" and .legendKeys == 5 and .legendLines == 1'
close_launcher

open_launcher
wtype "zz iconless"
until_ok 5000 state_is '.results[0] == "Zz Iconless" and .cursorBox != null'
check "artboard: an entry whose icon is missing gets the fallback tile ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] == "tile"'
tile=$(near "$(cursor_geo 20 20 16 16)" 242 243 246 2)
check "artboard: the fallback tile is #F2F3F6 ($tile of 256 px)" test "$tile" -gt 240
close_launcher

in_theme blueprint
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .cursorBox != null'
check "blueprint: the header reads LAUNCH // APPS and <n> MATCHES for the state's count ($(launcher_state | jq -c '[.label, .countText, .count]'))" state_is '.label == "LAUNCH // APPS" and .countText == "\(.count) MATCHES"'
check "blueprint: the cursor row's fill is #7FE3F0 and its first cell reads 01" state_is '.cursorFill == "#7fe3f0" and .slots[.selected] == "01"'
cyan=$(near "$(cursor_geo -60 3 8 8)" 127 227 240 3)
check "blueprint: inside the cursor row reads the accent ($cyan of 64 px)" test "$cyan" -eq 64
check "blueprint: the legend fits one line in apps mode ($(launcher_state | jq -c .legend))" state_is '.legendLines == 1 and .legendKeys == 5'
# The board restyles at once: the query and the keyboard stay while the cursor row turns Artboard's tint.
in_theme artboard
until_ok 2000 state_is '.cursorFill == "#eef1ff"'
check "switching to artboard while open restyles the cursor row and keeps the query" state_is '.open and .query == "fo" and .cursorFill == "#eef1ff" and .label == "Apps" and .keyboard'
tint=$(near "$(cursor_geo -70 4 8 8)" 238 241 255 3)
check "after the switch the cursor row draws the tint ($tint of 64 px)" test "$tint" -eq 64
close_launcher

for t in paper artboard blueprint; do
  in_theme "$t"
  open_launcher
  wtype "zz long"
  until_ok 3000 state_is '(.results[0] // "") | startswith("Zz Long")'
  check "$t: a 200-character name elides before the detail column ($(launcher_state | jq -c '[.cursorElided, .cursorDetailWidth]'))" state_is '.cursorElided and .cursorDetailWidth > 40'
  close_launcher
done

for m in "w " "v " ": " "= " "> "; do
  in_theme blueprint
  open_launcher
  wtype -- "$m"
  until_ok 2000 state_is ".query == \"$m\""
  check "blueprint: the legend fits one line in mode '$m'" state_is '.legendLines == 1'
  close_launcher
done

in_theme paper
exit $((fails > 0))
}
