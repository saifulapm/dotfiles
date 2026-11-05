#!/usr/bin/env bash
# The launcher looks like its board: icon tiles, a rounded tinted cursor row, a mode pill and prefix chips.
{
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
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
# An 8 px square in the query's empty right half, where only the card's fill shows.
fill_geo() { launcher_state | jq -r '.cardBox | "\(.x + 300 | floor),\(.y + 22 | floor) 8x8"'; }

# An app whose icon no theme has, written after the shell's scan, so the scan must pick it up.
mkdir -p "$DOTS_DEV_DIR/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Zz Iconless\nIcon=dots-no-such-icon\nExec=true\n' >"$DOTS_DEV_DIR/data/applications/dots-iconless.desktop"
long="Zz Long $(printf 'name%.0s' {1..48})"
printf '[Desktop Entry]\nType=Application\nName=%s\nGenericName=Long Detail\nExec=true\n' "$long" >"$DOTS_DEV_DIR/data/applications/dots-long.desktop"

until_ok 5000 shell_status >/dev/null

open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .results[0] == "Foot" and .cursorBox != null'
check "the cursor row's fill is #EEF1FF ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#eef1ff"'
tint=$(near "$(cursor_geo -70 4 8 8)" 238 241 255 3)
check "inside the cursor row reads the tint ($tint of 64 px)" test "$tint" -eq 64
corner=$(near "$(cursor_geo 0 0 2 2)" 255 255 255 3)
check "the cursor row's corner reads the card's white, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
check "Foot's row draws its icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] | test("^image://icon/foot")'
# foot's icon is a dark terminal, so its tile holds dark pixels that the tint never has.
dark=$(near "$(cursor_geo 12 12 32 32)" 30 30 30 40)
check "Foot's 32 px icon shows in its slot ($dark dark px)" test "$dark" -gt 100
check "the mode pill reads Apps and the footer shows five prefix chips" state_is '.label == "Apps" and .legendKeys == 5 and .legendLines == 1'
close_launcher

open_launcher
wtype "zz iconless"
until_ok 5000 state_is '.results[0] == "Zz Iconless" and .cursorBox != null'
check "an entry whose icon is missing gets the fallback tile ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] == "tile"'
tile=$(near "$(cursor_geo 20 20 16 16)" 242 243 246 2)
check "the fallback tile is #F2F3F6 ($tile of 256 px)" test "$tile" -gt 240
close_launcher

open_launcher
wtype "zz long"
until_ok 3000 state_is '(.results[0] // "") | startswith("Zz Long")'
check "a 200-character name elides above its detail ($(launcher_state | jq -c '[.cursorElided, .cursorDetailWidth]'))" state_is '.cursorElided and .cursorDetailWidth > 40'
close_launcher

for m in "w " "v " ": " "= " "> "; do
  open_launcher
  wtype -- "$m"
  until_ok 2000 state_is ".query == \"$m\""
  check "the legend fits one line in mode '$m'" state_is '.legendLines == 1'
  close_launcher
done

# Every mode draws its rows in the same look.
niri msg action spawn -- dots-call launcher mode clipboard
until_ok 3000 state_is '.open and .mode == "clipboard"'
check "Mod+V shows the mode pill reading Clipboard ($(launcher_state | jq -c .label))" state_is '.label == "Clipboard"'
close_launcher

open_launcher
wtype ": fire"
until_ok 3000 state_is '.results[0] == "🔥 fire" and .cursorBox != null'
check ": fire shows 🔥 in the first row's icon slot ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] == "🔥"'
flame=$(near "$(cursor_geo 12 12 32 32)" 245 130 40 60)
check "the flame's colours show in the slot ($flame px)" test "$flame" -gt 20
close_launcher

open_launcher
wtype "= 1440*1.25"
until_ok 3000 state_is '.mode == "calculator" and .results == ["1800"]'
check "= 1440*1.25 shows 1800 as the first row" state_is '.results[0] == "1800" and .label == "Calculator"'
close_launcher

niri msg action spawn -- foot -c /dev/null
until_ok 5000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"foot\")" >/dev/null'
open_launcher
wtype "w "
until_ok 3000 state_is '.mode == "windows" and (.results | length) >= 1'
check "a foot window's row draws foot's icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] | test("^image://icon/foot")'
close_launcher

# The card restyles at once: a switch while open keeps the query and the keyboard and fills the card in the new surface.
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo"'
"$repo/bin/dots" colorscheme catppuccin-mocha >/dev/null
until_ok 3000 eval 'shell_status | jq -e ".theme == \"catppuccin-mocha\" and .transition == \"\"" >/dev/null'
check "a switch while open keeps the query and the keyboard" state_is '.open and .query == "fo" and .keyboard'
fill=$(near "$(fill_geo)" 30 30 46 3)
check "the card is filled with Mocha's surface #1E1E2E ($fill of 64 px)" test "$fill" -eq 64
close_launcher

# A dark scheme's lit row is its own tint, mixed from its surface and accent, never Artboard's light #EEF1FF (m80 walk 0JG8TBA8).
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .cursorBox != null'
check "mocha: the cursor row's fill is its tint #2D334B ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#2d334b"'
tint=$(near "$(cursor_geo -70 4 8 8)" 45 51 75 3)
check "mocha: inside the cursor row reads #2D334B on screen ($tint of 64 px)" test "$tint" -eq 64
light=$(near "$(cursor_geo 0 0 400 20)" 238 241 255 6)
check "mocha: no pixel of the cursor row is Artboard's #EEF1FF ($light px)" test "$light" -eq 0
close_launcher

exit $((fails > 0))
}
