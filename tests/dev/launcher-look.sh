#!/usr/bin/env bash
# The launcher looks like board 3 on the island's fill: flat rows, a 32 px icon or a letter in a circle, a rounded fill on the selected row only, a long name elided beside its note.
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

# An app whose icon no theme has, written after the shell's scan, so the scan must pick it up.
mkdir -p "$DOTS_DEV_DIR/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Zz Iconless\nIcon=dots-no-such-icon\nExec=true\n' >"$DOTS_DEV_DIR/data/applications/dots-iconless.desktop"
long="Zz Long $(printf 'name%.0s' {1..48})"
printf '[Desktop Entry]\nType=Application\nName=%s\nGenericName=Long Detail\nExec=true\n' "$long" >"$DOTS_DEV_DIR/data/applications/dots-long.desktop"

until_ok 5000 shell_status >/dev/null

open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo" and .results[0] == "Foot" and .cursorBox != null'
check "the selected row's fill is the island's text at 7% ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#12e4e6ea"'
# The island is Artboard's ink #15171B, so the row's fill over it reads about 36 38 42.
tint=$(near "$(cursor_geo -70 4 8 8)" 36 38 42 4)
check "inside the selected row reads its fill over the island's ink ($tint of 64 px)" test "$tint" -eq 64
corner=$(near "$(cursor_geo 0 0 2 2)" 21 23 27 4)
check "the selected row's corner reads the island's ink, so it is rounded ($corner of 4 px)" test "$corner" -ge 3
check "Foot's row draws its icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] | test("^image://icon/foot")'
# foot's icon is a light page with a dark prompt, so its slot holds light pixels the ink never has.
lit=$(near "$(cursor_geo 10 8 32 32)" 230 230 220 40)
check "Foot's 32 px icon shows in its slot ($lit light px)" test "$lit" -gt 20
close_launcher

open_launcher
wtype "zz iconless"
until_ok 5000 state_is '.results[0] == "Zz Iconless" and .cursorBox != null'
check "an entry whose icon is missing draws its first letter in a circle ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] == "Z"'
close_launcher

open_launcher
wtype "zz long"
until_ok 3000 state_is '(.results[0] // "") | startswith("Zz Long")'
check "a 200-character name elides and leaves its note room ($(launcher_state | jq -c '[.cursorElided, .cursorDetailWidth]'))" state_is '.cursorElided and .cursorDetailWidth > 40'
close_launcher

open_launcher
wtype ": fire"
until_ok 3000 state_is '.results[0] == "🔥 fire" and .cursorBox != null'
check ": fire shows 🔥 as the first row's icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] == "🔥"'
flame=$(near "$(cursor_geo 10 8 32 32)" 245 130 40 60)
check "the flame's colours show in the slot ($flame px)" test "$flame" -gt 20
close_launcher

niri msg action spawn -- foot -c /dev/null
until_ok 5000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"foot\")" >/dev/null'
open_launcher
wtype "w "
until_ok 3000 state_is '.mode == "windows" and (.results | length) >= 1'
check "a foot window's row draws foot's icon ($(launcher_state | jq -c '.slots[0]'))" state_is '.slots[0] | test("^image://icon/foot")'
close_launcher

# The launcher restyles at once: a switch while open keeps the query and the keyboard, and the row's fill takes the new island's text.
open_launcher
wtype fo
until_ok 3000 state_is '.query == "fo"'
"$repo/bin/dots" colorscheme catppuccin-mocha >/dev/null
until_ok 3000 eval 'shell_status | jq -e ".theme == \"catppuccin-mocha\" and .transition == \"\"" >/dev/null'
check "a switch while open keeps the query and the keyboard" state_is '.open and .query == "fo" and .keyboard'
check "mocha: the selected row's fill is Mocha's text at 7% ($(launcher_state | jq -c .cursorFill))" state_is '.cursorFill == "#12cdd6f4"'
close_launcher

exit $((fails > 0))
}
