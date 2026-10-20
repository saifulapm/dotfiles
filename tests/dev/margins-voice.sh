#!/usr/bin/env bash
# The margins read in each theme's voice: 02 — FOOT · ~, Page 02 / foot — ~ and [02] FOOT — ~, each with its own date.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
drawn_is() { margins | jq -e --arg want "$2" ".drawn.$1 == \$want" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }

until_ok 5000 shell_status >/dev/null
# niri drops an empty workspace once focus leaves it, so workspace 1 keeps a window of its own.
niri msg action spawn -- foot -c /dev/null sleep 600
until_ok 5000 eval 'niri msg -j windows | jq -e "length == 1" >/dev/null'
niri msg action focus-workspace 2
# sleep never retitles its window the way a shell does, so the title stays ~.
niri msg action spawn -- foot -c /dev/null -T '~' sleep 600
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .title == "~" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused

# Each date reads in its theme's form.
date_ends() { margins | jq -e --arg d "$1" '.drawn.right | endswith($d)' >/dev/null 2>&1; }

in_theme paper
until_ok 2000 drawn_is left "02 — FOOT · ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "paper: the top-left reads 02 — FOOT · ~" drawn_is left "02 — FOOT · ~"
check "paper: the date reads $(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)" date_ends "$(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)"

in_theme artboard
until_ok 2000 drawn_is left "Page 02 / foot — ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "artboard: the top-left reads Page 02 / foot — ~" drawn_is left "Page 02 / foot — ~"
check "artboard: the date reads $(LC_ALL=C date +'%a %-d %b')" date_ends "$(LC_ALL=C date +'%a %-d %b')"

in_theme blueprint
until_ok 2000 drawn_is left "[02] FOOT — ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "blueprint: the top-left reads [02] FOOT — ~" drawn_is left "[02] FOOT — ~"
check "blueprint: the date reads $(date +%F)" date_ends "$(date +%F)"

# A title and a goal can be any length; each elides 8 px short of the island in every theme.
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
mkdir -p "$(dirname "$store")"
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
for t in paper artboard blueprint; do
  in_theme "$t"
  until_ok 2000 short_of_island
  echo "     $t: $(margins | jq -c '.drawn | {leftEnd, rightStart, lineEnd, width}')"
  check "$t: a 2000-character title and goal elide short of the island" short_of_island
done

exit $((fails > 0))
}
