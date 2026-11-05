#!/usr/bin/env bash
# The picker wears the current colorscheme on the one design: its cursor, current tag, header and keys, a card per scheme, and n cards share its width.
{
# Slowed, so the picker opens while the paper's switch still plays.
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$@" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
switch() { "$repo/bin/dots" colorscheme "$1" >/dev/null; }
shown() { state_is '.open and .settled'; }
gone() { state_is '.open == false'; }
open_picker() { niri msg action spawn -- dots-call themes toggle; until_ok 3000 shown; }
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
blue() { all_rgb 61 90 254 30; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 status_theme artboard

# Artboard: the cursor starts on the scheme in use.
open_picker
check "artboard: a card for each of the five schemes, light or dark, artboard first ($(themes_state | jq -c '[.cards[] | [.title, .tagline]]'))" \
  state_is '[.cards[] | [.title, .tagline]] == [["Artboard", "Light"], ["Catppuccin-mocha", "Dark"], ["Github-light", "Light"], ["Gruvbox-dark", "Dark"], ["Rose-pine-dawn", "Light"]]'
check "artboard: the header reads Themes 5 themes" state_is '.header == ["Themes5 themes", ""]'
check "artboard: the keys read j/k choose  1–5 jump  ↵ apply  esc ($(themes_state | jq -r .legend))" state_is '.legend == "j/k choose  1–5 jump  ↵ apply  esc"'
check "artboard: the current card shows Current" state_is '[.cards[].tag] == ["Current", "", "", "", ""]'
aligned() { state_is 'all(.cards[]; .tag == "" or ((.baselines[0] - .baselines[1]) | fabs) < 1)'; }
check "artboard: Current sits on its card name's baseline" aligned
wtype j
until_ok 1000 state_is '.selected == "catppuccin-mocha"'
sleep 0.3
read -r w h < <(card_size catppuccin-mocha)
check "artboard: j moves the cursor to catppuccin-mocha, which shows ↵, and Current stays" state_is '[.cards[].tag] == ["Current", "↵", "", "", ""]'
check "artboard: the cursor card reports a 1.5 px #3d5afe border" state_is '.cards[1].border == {"width": 1.5, "color": "#3d5afe"}'
white_tile() { card_grab catppuccin-mocha 4 $((h / 2)) 3 3 | all_rgb 255 255 255 2; }
check "artboard: the cursor card is #FFFFFF inside its outline" white_tile
blue_outline() { card_grab catppuccin-mocha -1 $((h / 2)) 3 2 | has_rgb 61 90 254 30; }
check "artboard: the cursor card has a #3D5AFE outline" blue_outline
no_shadow() { card_grab catppuccin-mocha $((w / 2)) $((h + 3)) 4 4 | all_rgb 255 255 255 6; }
check "artboard: under the cursor card the panel's white is bare, with no shadow" no_shadow
close_picker

# Gruvbox, opened while its crossfade still plays: the picker already wears it.
switch gruvbox-dark
until_ok 3000 status_theme gruvbox-dark
open_picker
check "gruvbox-dark: the picker opened while the paper's crossfade still ran" eval 'shell_status | jq -e ".transition == \"fade\"" >/dev/null'
check "gruvbox-dark: opened mid-switch, the current card is gruvbox-dark" state_is '.current == "gruvbox-dark" and .cards[3].tag == "Current"'
check "gruvbox-dark: the cursor card reports a 1.5 px #83a598 border" state_is '.cards[3].border == {"width": 1.5, "color": "#83a598"}'
read -r w h < <(card_size gruvbox-dark)
dark_tile() { card_grab gruvbox-dark 4 $((h / 2)) 3 3 | all_rgb 40 40 40 2; }
check "gruvbox-dark: the cursor card is #282828 inside its outline" dark_tile
close_picker
ended() { shell_status | jq -e '.transition == ""' >/dev/null; }
check "gruvbox-dark: once the switch ends, status reports no transition" until_ok 8000 ended

# The five schemes fit: five cards share the panel's width, none past its edge or over another.
list=$XDG_STATE_HOME/dots/theme-out/themes.json
open_picker
five_fit() {
  themes_state | jq -e '.cardBox as $p | (.cards | length == 5)
    and all(.cards[]; .box.x >= $p.x and .box.x + .box.w <= $p.x + $p.w + 0.5)
    and ([.cards[].box] | [range(1; 5) as $i | .[$i].x >= .[$i - 1].x + .[$i - 1].w] | all)
    and all(.cards[]; .preview.x >= .box.x and .preview.x + .preview.w <= .box.x + .box.w + 0.5)' >/dev/null
}
check "five cards share the panel's width without overlap, each specimen inside its card" five_fit
read -r sw < <(niri msg -j outputs | jq -r 'first(.[]).logical.width')
equal_fit() {
  themes_state | jq -e --argjson sw "$sw" '((([44 + 4 * 326 + 3 * 16, $sw - 48] | min) - 108) / 5 | [., 326] | min) as $fit
    | (.cards | length == 5) and all(.cards[]; (.box.w - $fit | fabs) < 0.5)' >/dev/null
}
check "five cards are each the fit wide" equal_fit
close_picker

# themes.json is a forged write: an entry the shell would refuse gets no card, and a name stays one line, in order, inside its card.
long=$(printf 'n%.0s' $(seq 200))
jq --arg long "$long" '[.[0], (.[1] | del(.niri) | .name = "noniri"), (.[1] | del(.color.ansi) | .name = "noansi"),
  (.[2] | del(.paper) | .name = "gruv\nbox\u202eevil"), (.[2] | .name = $long)]' "$list" >"$list.new" && mv "$list.new" "$list"
until_ok 2000 state_is '.themes | length == 3'
open_picker
check "forged entries without niri or ANSI get no card; the rest draw" state_is '[.cards[].name | .[0:4]] == ["artb", "gruv", "nnnn"] and all(.cards[]; .paperReady)'
check "a forged name draws on one line, in the order it is spelt" \
  state_is '.cards[1].title == "Gruv boxevil" and all(.cards[]; .nameLines == 1)'
check "a 200-character name is cut in its card's terminal line" state_is '.cards[2].terminal[3][1].text == "nnnnnnnn… on the shelf"'
check "a 200-character name elides inside its card" state_is 'all(.cards[]; (.nameRight | type) == "number" and .nameRight <= .box.x + .box.w)'
close_picker

# A sixth card shrinks them again, and none leaves the screen.
jq '. + [.[0] | .name = "sixth", .name = "seventh", .name = "eighth"]' "$list" >"$list.new" && mv "$list.new" "$list"
until_ok 2000 state_is '.themes | length == 6'
open_picker
inside() { themes_state | jq -e --argjson sw "$sw" '(.cards | length == 6) and all(.cards[]; .box.w < 326 and .box.x >= 0 and .box.x + .box.w <= $sw)' >/dev/null; }
check "six cards are each under 326 px and inside the screen" inside
close_picker

exit $((fails > 0))
}
