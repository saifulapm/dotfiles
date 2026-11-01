#!/usr/bin/env bash
# Hi-Fi's bar lights a pilot lamp before every workspace number, the shown one amber, draws a red lamp before the goal and an engraved groove under the bar.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
drawn() { margins | jq -e ".drawn | $1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
focused_is() { niri msg -j focused-window | jq -e --arg t "$1" '.title == $t' >/dev/null 2>&1; }
# niri drops an empty workspace once focus leaves it, so each numbered one keeps a window.
plain() { niri msg action spawn -- foot -c /dev/null -T "$1" sleep 600; until_ok 5000 focused_is "$1"; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
pixel() { grim -s 1 -t ppm -g "$((ox + $1)),$((oy + $2)) 1x1" - | mean_rgb; }
# Whether the pixel at x y is within $6 of r g b on each channel.
near() {
  local r g b
  read -r r g b < <(pixel "$1" "$2")
  ((r - $3 <= $6 && $3 - r <= $6 && g - $4 <= $6 && $4 - g <= $6 && b - $5 <= $6 && $5 - b <= $6))
}
# The centre of a box the margins report, as x y.
centre() { margins | jq -r ".drawn | $1 | .box | \"\(.x + .w / 2 | floor) \(.y + .h / 2 | floor)\""; }

until_ok 5000 shell_status >/dev/null

# Ship v2 is due in 71 hours, which the margin counts as 3D.
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
mkdir -p "$(dirname "$store")"
node --input-type=module - "$repo/shell/lib/goals.mjs" >"$store.tmp" <<'JS'
const G = await import(process.argv[2]);
console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'Ship v2', Date.now() + 71 * 3600000, Date.now(), 'g0')));
JS
mv "$store.tmp" "$store"

# Windows on 1 to 3 leave niri's empty workspace 4 after them.
plain ws1
for n in 2 3; do
  niri msg action focus-workspace "$n"
  plain "ws$n"
done
niri msg action focus-workspace 2
until_ok 2000 focused_is ws2

in_theme hi-fi
lamps_are() { drawn "[.lamps[] | [.idx, .lit]] == $1"; }
until_ok 2000 lamps_are '[[1,false],[2,true],[3,false],[4,false]]'
echo "     drawn: $(margins | jq -c '.drawn | {left, numbers, right, lamps: [.lamps[] | [.idx, .light]], goalLamp}')"
check "hi-fi: after focus-workspace 2, lamp 2 is lit and lamps 1, 3 and 4 are not" lamps_are '[[1,false],[2,true],[3,false],[4,false]]'
check "hi-fi: the numbers read 1 2 3 4, with no leading zero" drawn '.numbers == "1 2 3 4" and (.left | . == "1 2 3 4  FOOT  WS2")'
check "hi-fi: nothing the margins report holds a bracket ($(margins | marked | head -3 | paste -sd'|'))" eval '[ -z "$(margins | marked)" ]'

read -r lx ly < <(centre '.lamps[] | select(.idx == 2)')
until_ok 1000 near "$lx" "$ly" 250 189 47 12
check "hi-fi: lamp 2's centre reads #FABD2F ($(pixel "$lx" "$ly"))" near "$lx" "$ly" 250 189 47 12
read -r ux uy < <(centre '.lamps[] | select(.idx == 3)')
check "hi-fi: unlit lamp 3's centre reads #3C3836 ($(pixel "$ux" "$uy"))" near "$ux" "$uy" 60 56 54 8

until_ok 3000 drawn '.right | startswith("SHIP V2 · 3D")'
check "hi-fi: the goal reads SHIP V2 · 3D after a red lamp" drawn '(.right | startswith("SHIP V2 · 3D ")) and .goalLamp.light == "red"'
read -r gx gy < <(centre '.goalLamp')
check "hi-fi: the goal's lamp reads #FB4934 ($(pixel "$gx" "$gy"))" near "$gx" "$gy" 251 73 52 12
check "hi-fi: the date reads $(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)" drawn ".right | endswith(\"$(LC_ALL=C date +'%a %-d %b' | tr a-z A-Z)\")"

check "hi-fi: the row under the bar is the #0E0F10 groove ($(pixel 16 40))" near 16 40 14 15 16 3

# Windows on 4 to 8 leave workspace 9 empty after them.
for n in 4 5 6 7 8; do
  niri msg action focus-workspace "$n"
  plain "ws$n"
done
nine() { drawn '(.lamps | length) == 9'; }
until_ok 2000 nine
echo "     nine: $(margins | jq -c '.drawn | {numbers, last: .lamps[-1].box, islandLeft}')"
read -r nx ny < <(centre '.lamps[] | select(.idx == 8)')
check "hi-fi: with 9 workspaces, lamp 8 is lit ($(pixel "$nx" "$ny"))" near "$nx" "$ny" 250 189 47 12
check "hi-fi: the last lamp ends left of the island's left edge" drawn '(.lamps | length) == 9 and .lamps[-1].box.x + .lamps[-1].box.w < .islandLeft'

exit $((fails > 0))
}
