#!/usr/bin/env bash
# The margins read Page 02 / foot — ~ and the date as Thu 5 Nov, with an accent dot before the goal; a long title and goal elide short of the island.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
drawn_is() { margins | jq -e --arg want "$2" ".drawn.$1 == \$want" >/dev/null 2>&1; }
state_is() { margins | jq -e "$1" >/dev/null 2>&1; }

until_ok 5000 shell_status >/dev/null
# niri drops an empty workspace once focus leaves it, so workspace 1 keeps a window of its own.
niri msg action spawn -- foot -c /dev/null sleep 600
until_ok 5000 eval 'niri msg -j windows | jq -e "length == 1" >/dev/null'
niri msg action focus-workspace 2
# sleep never retitles its window the way a shell does, so the title stays ~.
niri msg action spawn -- foot -c /dev/null -T '~' sleep 600
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .title == "~" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused

date_ends() { margins | jq -e --arg d "$1" '.drawn.right | endswith($d)' >/dev/null 2>&1; }

until_ok 2000 drawn_is left "Page 02 / foot — ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "the top-left reads Page 02 / foot — ~" drawn_is left "Page 02 / foot — ~"
check "the date reads $(LC_ALL=C date +'%a %-d %b')" date_ends "$(LC_ALL=C date +'%a %-d %b')"

# A goal due in 3 days, so the goal item draws its dot.
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
mkdir -p "$(dirname "$store")"
node --input-type=module - "$repo/shell/lib/goals.mjs" >"$store.tmp" <<'JS'
const G = await import(process.argv[2]);
console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'Ship v2', Date.now() + 71 * 3600000, Date.now(), 'g0')));
JS
mv "$store.tmp" "$store"

near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
mean_at() { grim -s 1 -t ppm -g "$1" - | mean_rgb; }
# The 2 px square at the centre of the goal's 6 px dot.
dot_geo() { margins | jq -r '.drawn.dotBox | "\(.x + 2 | round),\(.y + 2 | round) 2x2"'; }
until_ok 3000 eval 'margins | jq -e ".drawn.right | startswith(\"Ship v2 · 3d \")" >/dev/null 2>&1'
check "the goal reads Ship v2 · 3d in ink #15171B ($(margins | jq -c '[.drawn.right, .drawn.goalColor]'))" state_is '(.drawn.right | startswith("Ship v2 · 3d ")) and .drawn.goalColor == "#15171b"'
check "the goal's dot is the accent #3D5AFE ($(mean_at "$(dot_geo)"))" near "$(mean_at "$(dot_geo)")" "61 90 254" 8

# A title and a goal can be any length; each elides 8 px short of the island.
node --input-type=module - "$repo/shell/lib/goals.mjs" >"$store.tmp" <<'JS'
const G = await import(process.argv[2]);
console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'G'.repeat(2000), Date.now() + 71 * 3600000, Date.now(), 'g0')));
JS
mv "$store.tmp" "$store"
niri msg action focus-workspace 3
niri msg action spawn -- foot -c /dev/null -T "$(printf 'T%.0s' $(seq 2000))" sleep 600
long_focused() { niri msg -j focused-window | jq -e '.title | length == 2000' >/dev/null 2>&1; }
until_ok 5000 long_focused
# A Text paints past its width unless it elides, so the check reads both its box and its elision.
short_of_island() { margins | jq -e '.drawn.left | length > 2000' >/dev/null 2>&1 && margins | jq -e '.drawn.leftElided and .drawn.goalElided and .drawn.leftEnd <= .drawn.lineEnd and .drawn.rightStart >= .drawn.width - .drawn.lineEnd' >/dev/null 2>&1; }
until_ok 2000 short_of_island
echo "     $(margins | jq -c '.drawn | {leftEnd, rightStart, lineEnd, width}')"
check "a 2000-character title and goal elide short of the island" short_of_island

exit $((fails > 0))
}
