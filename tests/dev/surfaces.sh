#!/usr/bin/env bash
# The launcher card is a white fill in a square 1 px line frame with no shadow, and the island is a square ink box.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null; }
launcher_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
launcher_open() { launcher_is ".open and .settled" && launcher_focus Exclusive; }
launcher_closed() { launcher_is ".open == false and .drawing == false" && launcher_focus None; }

read -r ox oy ow < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width)"')
# The launcher card's top-left corner, at x Math.round((width - 640) / 2) so an odd width rounds up, and the island's centre line.
cx=$((ox + (ow - 640 + 1) / 2))
cy=$((oy + 168))
mid=$((ox + ow / 2))

rgb() { grim -s 1 -t ppm -g "$1,$2 ${3:-1}x${4:-1}" - | mean_rgb; }
# Within tol per channel of r g b.
near() { local r g b t=${tol:-24}; read -r r g b < <(rgb "$1" "$2" "${6:-1}" "${7:-1}"); ((r - $3 <= t && $3 - r <= t && g - $4 <= t && $4 - g <= t && b - $5 <= t && $5 - b <= t)); }
light() { local r g b; read -r r g b < <(rgb "$1" "$2"); ((r > 150 && g > 150 && b > 150)); }
ink() { near "$1" "$2" 21 23 27 "${3:-1}" "${4:-1}"; }
# Artboard's line #D0D7DE, close enough that the paper #E4E6EA is not it.
line() { tol=8 near "$1" "$2" 208 215 222 "${3:-1}" "${4:-1}"; }
# A panel's edge near its top left: Artboard's accent #3D5AFE, before it fades toward the paper.
edge() { tol=40 near "$1" "$2" 61 90 254 "${3:-1}" "${4:-1}"; }
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

until_ok 5000 shell_status >/dev/null

niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_open
check "the launcher reports its card at rest, 640 px wide at y 168 ($(launcher_state | jq -c .cardBox))" launcher_is ".cardBox.x == $((cx - ox)) and .cardBox.y == 168 and .cardBox.w == 640"
# The accent edge runs down the left side to the corner itself, so the corner is square; inside it the card is the paper, and 2 px outside it the wash shows no shadow.
card() { edge "$cx" "$cy" && edge "$cx" $((cy + 40)) 1 10 && tol=6 near $((cx + 100)) $((cy + 3)) 228 230 234 && ! ink $((cx + 640 + 2)) $((cy + 60)) && ! ink $((cx - 2)) $((cy + 40)); }
until_ok 2000 card
check "the card is the paper in a square 1 px accent edge, with no shadow past it" card
wtype -k Escape
until_ok 2000 launcher_closed

# Its left edge is ink up at y 10 as well as on the middle row, so the corner is square, and 2 px left of it is paper.
island() { local l r; read -r l r < <(span 21 23 27); ((l >= 2)) && ink $((mid - 200 + l)) $((oy + 10)) && ink $((mid - 200 + l + 5)) $((oy + 27)) && light $((mid - 200 + l - 2)) $((oy + 10)); }
until_ok 2000 island
check "the island is a square ink box on the paper" island

exit $((fails > 0))
}
