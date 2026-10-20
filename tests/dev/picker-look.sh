#!/usr/bin/env bash
# The picker wears the current theme: each theme's cursor, current tag, header and keys, and n cards share its width.
{
# Slowed, so the picker opens while the paper's switch still plays.
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$@" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}
shown() { state_is '.open and .settled'; }
gone() { state_is '.open == false'; }
open_picker() { niri msg action spawn -- qs ipc call themes toggle; until_ok 3000 shown; }
close_picker() { wtype -k Escape; until_ok 2000 gone; }
# The PPM of a w x h region at x,y relative to card $1's drawn box.
card_grab() {
  local x y
  read -r x y < <(themes_state | jq -r --arg n "$1" --argjson ox "$ox" --argjson oy "$oy" '.cards[] | select(.name == $n) | .box | "\(.x + $ox | round) \(.y + $oy | round)"')
  grim -s 1 -t ppm -g "$((x + $2)),$((y + $3)) ${4}x${5}" -
}
card_size() { themes_state | jq -r --arg n "$1" '.cards[] | select(.name == $n) | .box | "\(.w | round) \(.h | round)"'; }
has_rgb() {
  node -e '
    const [r, g, b, tol] = process.argv.slice(1).map(Number);
    const buf = require("fs").readFileSync(0);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = buf.subarray(head[0].length);
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) {
      if (Math.abs(px[i] - r) <= tol && Math.abs(px[i + 1] - g) <= tol && Math.abs(px[i + 2] - b) <= tol) process.exit(0);
    }
    process.exit(1);
  ' "$@"
}
# Exits 0 when every pixel of the PPM on stdin is within $4 per channel of $1 $2 $3.
all_rgb() {
  node -e '
    const [r, g, b, tol] = process.argv.slice(1).map(Number);
    const buf = require("fs").readFileSync(0);
    const head = buf.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = buf.subarray(head[0].length);
    for (let i = 0; i < head[1] * head[2] * 3; i += 3) {
      if (Math.abs(px[i] - r) > tol || Math.abs(px[i + 1] - g) > tol || Math.abs(px[i + 2] - b) > tol) process.exit(1);
    }
  ' "$@"
}
vermilion() { all_rgb 200 56 30 10; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 status_theme paper

# Paper: the cursor starts on paper, the current theme.
open_picker
read -r w h < <(card_size paper)
border_2px() { card_grab paper 0 $((h / 2)) 2 4 | vermilion && ! card_grab paper 2 $((h / 2)) 1 4 | vermilion; }
check "paper: the cursor card's left edge is 2 px of #C8381E, then not" border_2px
shadow_4px() { card_grab paper $((w / 2)) "$h" 4 4 | vermilion && ! card_grab paper $((w / 2)) $((h + 4)) 4 1 | vermilion; }
check "paper: under the cursor card lies a 4 px #C8381E hard shadow, then not" shadow_4px
check "paper: the cursor card reports a 2 px #c8381e border" state_is '.cards[0].border == {"width": 2, "color": "#c8381e"}'
check "paper: the current card shows IN USE" state_is '[.cards[].tag] == ["IN USE", "", ""]'
check "paper: the header reads Themes three on the shelf, PAPER IN USE" state_is '.header == ["Themesthree on the shelf", "PAPER IN USE"]'
aligned() { state_is '(.headerBaselines[0] - .headerBaselines[1] | fabs) < 1 and all(.cards[]; .tag == "" or ((.baselines[0] - .baselines[1]) | fabs) < 1)'; }
check "paper: PAPER IN USE and IN USE sit on the header's and the name's baselines" aligned
check "paper: the keys read J/K CHOOSE  1–3 JUMP  ↵ APPLY  ESC" state_is '.legend == "J/K CHOOSE  1–3 JUMP  ↵ APPLY  ESC"'
wtype j
until_ok 1000 state_is '.selected == "artboard"'
check "paper: j moves the vermilion border to artboard and IN USE stays on paper" \
  state_is '.cards[1].border.color == "#c8381e" and .cards[0].border.color != "#c8381e" and .cards[0].tag == "IN USE"'
close_picker

# Artboard, opened while its switch transition still plays: the picker already wears it.
switch artboard
until_ok 3000 status_theme artboard
open_picker
# Paper's motion is snappy, so the switch away from it is a slide; .current names the theme whether or not the paper still moves, status reads the paper's running kind.
check "artboard: the picker opened while the paper's slide still ran" eval 'shell_status | jq -e ".transition == \"slide\"" >/dev/null'
check "artboard: opened mid-switch, the current card is artboard" state_is '.current == "artboard" and .cards[1].tag == "Current"'
wtype k
until_ok 1000 state_is '.selected == "paper"'
sleep 0.3
read -r w h < <(card_size paper)
white_tile() { card_grab paper 4 $((h / 2)) 3 3 | all_rgb 255 255 255 2; }
check "artboard: the cursor card is #FFFFFF inside its outline" white_tile
blue_outline() { card_grab paper -1 $((h / 2)) 3 2 | has_rgb 61 90 254 30; }
check "artboard: the cursor card has a #3D5AFE outline" blue_outline
check "artboard: the cursor card reports a 1.5 px #3d5afe border" state_is '.cards[0].border == {"width": 1.5, "color": "#3d5afe"}'
check "artboard: the cursor card shows ↵ and the current shows Current" state_is '[.cards[].tag] == ["↵", "Current", ""]'
frame_label() {
  local x y
  read -r x y < <(themes_state | jq -r --argjson ox "$ox" --argjson oy "$oy" '.cardBox | "\(.x + $ox | round) \(.y + $oy | round)"')
  grim -s 1 -t ppm -g "$x,$((y - 20)) 60x16" - | has_rgb 61 90 254 30
}
check "artboard: the panel has its blue Themes frame label" frame_label
check "artboard: the header reads Themes 3 themes" state_is '.header == ["Themes3 themes", ""]'
close_picker
ended() { shell_status | jq -e '.transition == ""' >/dev/null; }
check "artboard: once the switch ends, status reports no transition" until_ok 8000 ended

switch blueprint
until_ok 3000 status_theme blueprint
open_picker
check "blueprint: the header reads THEMES // 3 SHEETS, ACTIVE: BLUEPRINT" state_is '.header == ["THEMES // 3 SHEETS", "ACTIVE: BLUEPRINT"]'
check "blueprint: each name follows its number 01 to 03" \
  state_is '[.cards[] | .number + " " + .title] == ["01 Paper", "02 Artboard", "03 BLUEPRINT"]'
check "blueprint: the current card shows [ACTIVE]" state_is '[.cards[].tag] == ["", "", "[ACTIVE]"]'
check "blueprint: ACTIVE: BLUEPRINT and [ACTIVE] sit on the header's and the name's baselines" aligned
check "blueprint: the keys are bracketed" state_is '.legend == "[J/K] CHOOSE  [1–3] JUMP  [↵] APPLY  [ESC]"'
close_picker

# A fourth theme fits: four cards share the panel's width, none past its edge or over another.
list=$XDG_STATE_HOME/dots/theme-out/themes.json
jq '. + [(.[2] | .name = "blueprint2")]' "$list" >"$list.new" && mv "$list.new" "$list"
until_ok 2000 state_is '.themes | length == 4'
open_picker
four_fit() {
  themes_state | jq -e '.cardBox as $p | (.cards | length == 4)
    and all(.cards[]; .box.x >= $p.x and .box.x + .box.w <= $p.x + $p.w + 0.5)
    and ([.cards[].box] | [range(1; 4) as $i | .[$i].x >= .[$i - 1].x + .[$i - 1].w] | all)
    and all(.cards[]; .preview.x >= .box.x and .preview.x + .preview.w <= .box.x + .box.w + 0.5)' >/dev/null
}
check "four cards share the panel's width without overlap, each specimen inside its card" four_fit
check "the header counts four sheets and the keys jump 1–4" state_is '.header[0] == "THEMES // 4 SHEETS" and (.legend | contains("[1–4] JUMP"))'
close_picker

# themes.json is a forged write: an entry the shell would refuse gets no card, and a name stays one line, in order, inside its card.
long=$(printf 'n%.0s' $(seq 200))
jq --arg long "$long" '[.[0], (.[1] | del(.niri) | .name = "noniri"), (.[1] | del(.color.ansi) | .name = "noansi"),
  (.[2] | del(.paper) | .name = "blue\nprint\u202eevil"), (.[2] | .name = $long)]' "$list" >"$list.new" && mv "$list.new" "$list"
until_ok 2000 state_is '.themes | length == 3'
open_picker
check "forged entries without niri or ANSI get no card; the rest draw" state_is '[.cards[].name | .[0:4]] == ["pape", "blue", "nnnn"] and all(.cards[]; .paperReady)'
check "a forged name draws on one line, in the order it is spelt" \
  state_is '.cards[1].title == "BLUE PRINTEVIL" and all(.cards[]; .nameLines == 1)'
check "a 200-character name is cut in its card's terminal line" state_is '.cards[2].terminal[3][1].text == "nnnnnnnn… on the shelf"'
check "a 200-character name elides inside its card" state_is 'all(.cards[]; (.nameRight | type) == "number" and .nameRight <= .box.x + .box.w)'
close_picker

exit $((fails > 0))
}
