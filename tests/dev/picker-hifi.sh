#!/usr/bin/env bash
# In Hi-Fi the picker wears its receiver's board: four sources, an amber cursor over #3C3836 cards, a green lamp by IN USE, and the Hi-fi card's own palette; Paper keeps its shelf.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$@" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
read -r sw < <(niri msg -j outputs | jq -r 'first(.[]).logical.width')
switch() {
  node "$repo/shell/lib/theme-render.mjs" "$1" >/dev/null
  printf '%s\n' "$1" >"$XDG_STATE_HOME/dots/theme"
}
open_picker() { niri msg action spawn -- dots-call themes toggle; until_ok 3000 state_is '.open and .settled and all(.cards[]; .paperReady)'; }
close_picker() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
hex_rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
# Exits 0 when the "r g b" in $1 is within $3 per channel of the hex colour $2.
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$(hex_rgb "$2")"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
# The mean colour of the w x h region at x,y of a box ($1, a jq path into the state), as "r g b".
box_rgb() {
  local x y
  read -r x y < <(themes_state | jq -r --argjson ox "$ox" --argjson oy "$oy" "$1 | \"\(.x + \$ox | round) \(.y + \$oy | round)\"")
  grim -s 1 -t ppm -g "$((x + $2)),$((y + $3)) ${4}x${5}" - | mean_rgb
}
card_h() { themes_state | jq -r --arg n "$1" '.cards[] | select(.name == $n) | .box.h | round'; }
card_box() { printf '.cards[] | select(.name == "%s") | .box' "$1"; }

until_ok 5000 shell_status >/dev/null
switch hi-fi
until_ok 3000 status_theme hi-fi
open_picker

four_fit() {
  themes_state | jq -e --argjson sw "$sw" '((([44 + 4 * 326 + 3 * 16, $sw - 48] | min) - 92) / 4 | [., 326] | min) as $fit
    | (.cards | length == 4) and all(.cards[]; (.box.w - $fit | fabs) < 0.5)' >/dev/null
}
check "hi-fi: four cards, each min(326, fit) wide" four_fit
check "hi-fi: the header reads THEMES · 4 SOURCES and IN USE: HI-FI ($(themes_state | jq -c .header))" \
  state_is '.header == ["THEMES · 4 SOURCES", "IN USE: HI-FI"]'
check "hi-fi: the Hi-fi card's swatches are its surface and bright ANSI 9 to 15, in order" \
  state_is '[.cards[] | select(.name == "hi-fi") | .swatches[].color | ascii_upcase] == ["#282828", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"]'
# A 4x4 grab 3 px down a swatch, about its middle.
swatch() { box_rgb ".cards[3].swatches[$1]" "$(themes_state | jq -r --argjson i "$1" '.cards[3].swatches[$i].w / 2 - 2 | round')" 3 4 4; }
first_swatch() { near "$(swatch 0)" '#282828' 6; }
check "hi-fi: a grim of the first swatch reads #282828 ($(swatch 0))" first_swatch
fourth_swatch() { near "$(swatch 3)" '#FABD2F' 6; }
check "hi-fi: a grim of the fourth swatch reads #FABD2F ($(swatch 3))" fourth_swatch

# The cursor opens on the theme in use, the Hi-fi card; Paper's card is unfocused.
check "hi-fi: the cursor is on the Hi-fi card, Paper's is not" state_is '.selected == "hi-fi"'
cursor_edge() { near "$(box_rgb "$(card_box hi-fi)" 0 $(($(card_h hi-fi) / 2)) 1 4)" '#FABD2F' 12; }
check "hi-fi: a grim of the cursor card's left border reads amber ($(box_rgb "$(card_box hi-fi)" 0 $(($(card_h hi-fi) / 2)) 1 4))" cursor_edge
tile_edge() { near "$(box_rgb "$(card_box paper)" 0 $(($(card_h paper) / 2)) 1 4)" '#3C3836' 8; }
check "hi-fi: a grim of an unfocused card's left border reads #3C3836 ($(box_rgb "$(card_box paper)" 0 $(($(card_h paper) / 2)) 1 4))" tile_edge
check "hi-fi: the Hi-fi card's tag reads IN USE after a green lamp" state_is '.cards[3].tag == "IN USE" and .cards[3].lamp.light == "green"'
# The name, the tagline and IN USE share one line, as the board draws them; the tagline must not give way to the tag.
check "hi-fi: the Hi-fi card's tagline reads BRUSHED · AMBER · DIAL whole beside IN USE ($(themes_state | jq -c '.cards[3] | [.tagline, .taglineElided, .box.w]'))" state_is '.cards[3].tagline == "BRUSHED · AMBER · DIAL" and .cards[3].taglineElided == false'
lamp_rgb() { box_rgb '.cards[3].lamp.box' 2 2 2 2; }
green_lamp() { near "$(lamp_rgb)" '#B8BB26' 12; }
check "hi-fi: a grim of the in-use lamp reads #B8BB26 ($(lamp_rgb))" green_lamp

# The cursor lands on the Hi-fi card from Blueprint's: its sweep plays in 220 ms.
wtype k
until_ok 2000 state_is '.selected == "blueprint" and .played.ms >= 0'
wtype j
until_ok 2000 state_is '.played.name == "hi-fi" and .played.ms >= 0'
check "hi-fi: the cursor onto the Hi-fi card plays its sweep in 210 to 240 ms ($(themes_state | jq -c .played))" \
  state_is '.played.name == "hi-fi" and .played.ms >= 210 and .played.ms <= 240'
close_picker

switch paper
until_ok 3000 status_theme paper
open_picker
check "paper: the picker still reads Themes four on the shelf, PAPER IN USE" state_is '.header == ["Themesfour on the shelf", "PAPER IN USE"]'
close_picker

exit $((fails > 0))
}
