#!/usr/bin/env bash
# Each theme's launcher card and island carry a mark that only that theme's primitives draw.
source "$(dirname "$0")/lib.sh"
unset TMUX

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
launcher_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
launcher_open() { launcher_is .open && launcher_focus Exclusive; }
launcher_closed() { launcher_is '.open == false' && launcher_focus None; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')
# The launcher card's top-left corner and the island's centre line, in screen pixels.
cx=$((ox + (ow - 640) / 2))
cy=$((oy + 168))
mid=$((ox + ow / 2))

rgb() { grim -s 1 -t ppm -g "$1,$2 ${3:-1}x${4:-1}" - | mean_rgb; }
# Within tol per channel of r g b; Blueprint's surface and paper differ by 8 at most, so its checks pass tol=4.
near() { local r g b t=${tol:-24}; read -r r g b < <(rgb "$1" "$2" "${6:-1}" "${7:-1}"); ((r - $3 <= t && $3 - r <= t && g - $4 <= t && $4 - g <= t && b - $5 <= t && $5 - b <= t)); }
light() { local r g b; read -r r g b < <(rgb "$1" "$2"); ((r > 150 && g > 150 && b > 150)); }
# The first and last x on the island's middle row within 40 per channel of a colour, as "left right".
span() {
  grim -s 1 -t ppm -g "$((mid - 200)),$((oy + 27)) 400x1" - | node -e '
    const b = require("fs").readFileSync(0), want = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    const hit = [];
    for (let x = 0; x < head[1]; x++) if ([0, 1, 2].every((i) => Math.abs(px[x * 3 + i] - want[i]) <= 40)) hit.push(x);
    console.log(hit.length ? `${hit[0]} ${hit[hit.length - 1]}` : "-1 -1");
  ' "$@"
}

show() {
  "$repo/bin/dots" theme "$1" >/dev/null
  until_ok 2000 status_theme "$1"
  niri msg action spawn -- qs ipc call launcher toggle
  until_ok 3000 launcher_open
}
hide() {
  wtype -k Escape
  until_ok 2000 launcher_closed
}

until_ok 5000 shell_status >/dev/null

show paper
# Paper's card shadow is a hard ink block from 0 to 6 px past the card's right edge, then the wash.
paper_card() { near $((cx + 643)) $((cy + 60)) 28 25 21 && ! near $((cx + 648)) $((cy + 60)) 28 25 21; }
until_ok 2000 paper_card
check "paper: the launcher card casts a hard ink shadow 6 px right" paper_card
hide
paper_island() { local l r; read -r l r < <(span 28 25 21); ((r > 0)) && near $((mid - 200 + r + 2)) $((oy + 27)) 200 56 30; }
until_ok 2000 paper_island
check "paper: the island's vermilion shadow shows 3 px right of its ink box" paper_island

show artboard
# Artboard's handle is an accent ring centred on the card's corner, over a white card.
artboard_card() { near $((cx - 4)) "$cy" 61 90 254 && near $((cx + 100)) $((cy + 3)) 255 255 255; }
until_ok 2000 artboard_card
check "artboard: an accent handle sits on the card's corner and the card is white" artboard_card
hide
artboard_island() { local l r; read -r l r < <(span 21 23 27); ((l >= 0)) && light $((mid - 200 + l)) $((oy + 10)) && near $((mid - 200 + l + 5)) $((oy + 27)) 21 23 27; }
until_ok 2000 artboard_island
check "artboard: the island is an ink pill, its corner left as paper" artboard_island

show blueprint
# Blueprint's chamfer cuts the corner: the left edge's first 8 px have no cyan stroke, lower down they do.
cyan() { near "$1" "$2" 127 227 240 "${3:-1}" "${4:-1}"; }
blueprint_card() { ! cyan "$cx" "$cy" 1 8 && cyan "$cx" $((cy + 40)) 1 10 && ! tol=4 near $((cx + 1)) $((cy + 1)) 10 21 38 && tol=4 near $((cx + 30)) $((cy + 3)) 10 21 38; }
until_ok 2000 blueprint_card
check "blueprint: the card's top-left corner is cut and its stroke runs below the chamfer" blueprint_card
hide
blueprint_island() { cyan "$mid" $((oy + 10)); }
until_ok 2000 blueprint_island
check "blueprint: the island's top edge is the cyan stroke" blueprint_island

"$repo/bin/dots" theme paper >/dev/null
exit $((fails > 0))
