#!/usr/bin/env bash
# Board 2's one-line states: each is a 14 px filled icon, its short text, then the clock pinned at the box's right, 34 px tall.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
settled() { island_is "$1 and .animating == false"; }
music=$(printf '\U000F075A')

until_ok 3000 settled '.mode == "rest"'
"$repo/bin/dev-fake-mpris" "Paranoid Android" Radiohead &
player=$!
cleanup() { kill "$player" 2>/dev/null; }
until_ok 3000 settled '.mode == "playing"'
echo "     live: $(island | jq -c .live)"
check "with music playing the island draws a music icon and the track's title ($(island | jq -c '[.live.icon, .live.text]'))" island_is --arg i "$music" '.live.icon == $i and .live.text == "Paranoid Android" and .live.elided == false'
check "and the clock, 14 px in from the box's right edge ($(island | jq -c '[.live.clock, .live.clockRight]'))" island_is --arg c "$(date +%H:%M)" '.live.clock == $c and .live.clockRight == 14'
check "in one 34 px line ($(island | jq -c '[.width, .height]'))" island_is '.height == 34 and .width > 176 and .width < 400'
check "island state's text stays the canonical one" island_is --arg t "Paranoid Android — Radiohead  $(date +%H:%M)" '.text == $t'
kill "$player"
until_ok 3000 settled '.mode == "rest"'

long=$(printf 'Long%.0s' {1..50})
"$repo/bin/dev-fake-mpris" "$long" Artist &
player=$!
until_ok 3000 settled '.mode == "playing"'
check "a 200-character title is cut with an ellipsis ($(island | jq -c '.live.elided'))" island_is '.live.elided == true'
check "the island stays at its widest line, 560 px ($(island | jq .width))" island_is '.width == 560 and .height == 34'
check "and the clock is still at the box's right edge, clear of the title ($(island | jq -c '[.live.clockRight, .live.textRight, .live.clockLeft]'))" island_is '.live.clockRight == 14 and .live.textRight <= .live.clockLeft - 16'
exit "$fails"
}
