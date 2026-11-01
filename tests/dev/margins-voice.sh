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

in_theme hi-fi
until_ok 2000 drawn_is left "1 2 3  FOOT  ~"
echo "     drawn: $(margins | jq -c .drawn)"
check "hi-fi: the top-left reads 1 2 3  FOOT  ~, a number for each workspace" drawn_is left "1 2 3  FOOT  ~"
check "hi-fi: the date reads $(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)" date_ends "$(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)"
check "hi-fi: nothing the margins report holds a bracket ($(margins | marked | head -3 | paste -sd'|'))" eval '[ -z "$(margins | marked)" ]'
check "hi-fi: the labels are engraved" eval 'margins | jq -e ".drawn.raised == true" >/dev/null'
# The line sits under the letters: the row below the number's last amber row is lit; a row of bare faceplate further down is not.
under_line() {
  local g
  g=$(margins | jq -r '.drawn.numberBox | "\(.x | floor),\(.y | floor) \(.w | ceil)x\(.h + 6 | ceil)"')
  grim -s 1 -t ppm -g "$g" - | node -e '
    const b = require("fs").readFileSync(0), head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    const [w, h] = [+head[1], +head[2]], at = (x, y) => px.subarray((y * w + x) * 3, (y * w + x) * 3 + 3);
    const amber = (p) => p[0] > 180 && p[2] < 120;
    let last = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (amber(at(x, y))) last = y;
    const lit = (y) => { let n = 0; for (let x = 0; x < w; x++) { const p = at(x, y); if (!amber(p) && p[0] >= 40) n++; } return n; };
    console.log(last, lit(last + 1), lit(Math.min(h - 1, last + 4)));
  '
}
read -r last below bare < <(under_line)
check "hi-fi: under the number's last amber row ($last) $below pixels are lit, against $bare on bare faceplate" test "$below" -ge $((bare + 3))
in_theme blueprint
check "blueprint: its labels are not engraved" eval 'margins | jq -e ".drawn.raised == false" >/dev/null'

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
