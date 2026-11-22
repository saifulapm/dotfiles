#!/usr/bin/env bash
# The resting island hugs the top edge: 34 px tall and as wide as its content, two 12 px concave corners joining it to the edge, 14 px bottom corners, no frame and no shadow, in the scheme's island fill.
{
export DOTS_DEV_SCHEME=github-light
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$1" >/dev/null 2>&1; }
# One output pixel as #RRGGBB.
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n' | tr a-f A-F | sed 's/^/#/'; }
px_is() { [ "$(px "$1" "$2")" = "$3" ]; }
# The paper is graded, so a pixel is the paper's when each channel is within 8 of an 8 x 8 patch's mean 24 px below it, clear of the island.
paper_near() {
  local want got
  want=$(grim -g "$(($1 - 4)),$(($2 + 24)) 8x8" -t ppm - 2>/dev/null | mean_rgb)
  got=$(px "$1" "$2")
  node -e 'const [r, g, b] = process.argv[1].split(" ").map(Number), h = process.argv[2]; const p = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)); process.exit([r, g, b].every((v, i) => Math.abs(v - p[i]) <= 8) ? 0 : 1)' "$want" "$got"
}

until_ok 3000 eval "shell_status | jq -e '.theme == \"github-light\" and .transition == \"\"' >/dev/null"
until_ok 3000 island_is '.mode == "rest" and .animating == false'
today=$(LC_ALL=C date '+%a %-d %b')
check "at rest the island is 34 px tall and reads today's date, $today ($(island | jq -c '{width, height, rest}'))" island_is ".height == 34 and .width > 0 and .rest.date == \"$today\""
read -r bx by bw bh < <(timeout 0.5 qs ipc call island box island | jq -r '"\(.x | floor) \(.y | floor) \(.w | floor) \(.h | floor)"')
cx=$((bx + bw / 2))
check "the island's box starts on the output's top row (y $by)" test "$by" -eq 0
check "in GitHub Light the island's centre on the top row is #1F2328 ($(px "$cx" 0))" px_is "$cx" 0 "#1F2328"
check "2 px left of the box on the top row is the fill, inside the concave corner ($(px $((bx - 2)) 0))" px_is $((bx - 2)) 0 "#1F2328"
check "and 2 px right of it too ($(px $((bx + bw + 1)) 0))" px_is $((bx + bw + 1)) 0 "#1F2328"
check "12 px left of and 12 px below the box's top left corner is the paper, outside the corner ($(px $((bx - 12)) 12))" paper_near $((bx - 12)) 12
check "the box's last row at its centre is the fill ($(px "$cx" $((by + bh - 1))))" px_is "$cx" $((by + bh - 1)) "#1F2328"
check "and the row below it is the paper, with no frame or shadow between ($(px "$cx" $((by + bh))))" paper_near "$cx" $((by + bh))
check "a 14 px bottom corner leaves the box's bottom left pixel to the paper ($(px "$bx" $((by + bh - 1))))" paper_near "$bx" $((by + bh - 1))

"$repo/bin/dots" colorscheme catppuccin-mocha >/dev/null
switched() { shell_status | jq -e '.theme == "catppuccin-mocha" and .transition == ""' >/dev/null && island_is '.fill.color == "#1e1e2e" and .fill.endedAt > .fill.startedAt'; }
until_ok 3000 switched
took=$(($(island | jq .fill.endedAt) - $(shell_status | jq .transitionStartedAt)))
check "after the switch to Catppuccin Mocha the island's fill ends at #1E1E2E within 300 ms of the paper's switch starting (${took} ms, $(px "$cx" 0))" test "$took" -le 300 -a "$(px "$cx" 0)" = "#1E1E2E"
exit "$fails"
}
