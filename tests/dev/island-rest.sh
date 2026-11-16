#!/usr/bin/env bash
# The resting island hugs the top edge: 176 x 34, two 12 px concave corners joining it to the edge, 14 px bottom corners, no frame and no shadow, in the scheme's island fill.
{
export DOTS_DEV_SCHEME=github-light
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$1" >/dev/null 2>&1; }
# One output pixel as #RRGGBB.
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n' | tr a-f A-F | sed 's/^/#/'; }
px_is() { [ "$(px "$1" "$2")" = "$3" ]; }
paper_of() { sed -n 's/^paper = "\(#[0-9A-Fa-f]*\)"/\1/p' "$repo/colorschemes/$1.toml" | tr a-f A-F; }

until_ok 3000 eval "shell_status | jq -e '.theme == \"github-light\" and .transition == \"\"' >/dev/null"
until_ok 3000 island_is '.mode == "rest" and .animating == false'
check "at rest the island is 176 x 34 ($(island | jq -c '{width, height}'))" island_is '.width == 176 and .height == 34'
read -r bx by bw bh < <(timeout 0.5 qs ipc call island box island | jq -r '"\(.x | floor) \(.y | floor) \(.w | floor) \(.h | floor)"')
cx=$((bx + bw / 2))
check "the island's box starts on the output's top row (y $by)" test "$by" -eq 0
check "in GitHub Light the island's centre on the top row is #1F2328 ($(px "$cx" 0))" px_is "$cx" 0 "#1F2328"
check "2 px left of the box on the top row is the fill, inside the concave corner ($(px $((bx - 2)) 0))" px_is $((bx - 2)) 0 "#1F2328"
check "and 2 px right of it too ($(px $((bx + bw + 1)) 0))" px_is $((bx + bw + 1)) 0 "#1F2328"
paper=$(paper_of github-light)
check "12 px left of and 12 px below the box's top left corner is the paper, outside the corner ($(px $((bx - 12)) 12), paper $paper)" px_is $((bx - 12)) 12 "$paper"
check "the box's last row at its centre is the fill ($(px "$cx" $((by + bh - 1))))" px_is "$cx" $((by + bh - 1)) "#1F2328"
check "and the row below it is the paper, with no frame or shadow between ($(px "$cx" $((by + bh))))" px_is "$cx" $((by + bh)) "$paper"
check "a 14 px bottom corner leaves the box's bottom left pixel to the paper ($(px "$bx" $((by + bh - 1))))" px_is "$bx" $((by + bh - 1)) "$paper"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
gap=$(margins | jq -r '.drawn | (.islandLeft - .lineEnd) | floor')
check "the margins' rules end 8 px short of the concave corner, 20 px from the box ($gap)" test "$gap" -eq 20

"$repo/bin/dots" colorscheme catppuccin-mocha >/dev/null
until_ok 3000 eval "shell_status | jq -e '.theme == \"catppuccin-mocha\"' >/dev/null"
t0=$(now_ms)
until_ok 1000 px_is "$cx" 0 "#1E1E2E"
took=$(($(now_ms) - t0))
check "after the switch to Catppuccin Mocha the island's fill is #1E1E2E within 300 ms (${took} ms, $(px "$cx" 0))" test "$took" -le 300 -a "$(px "$cx" 0)" = "#1E1E2E"
exit "$fails"
}
