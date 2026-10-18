#!/usr/bin/env bash
# Mod+Shift+T opens the theme switcher, j/k move the cursor, Enter applies through dots theme, Esc closes.
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_shift_t() { niri msg action spawn -- qs ipc call themes toggle; }
themes_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-themes" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# The right edge of the Blueprint card's preview, Blueprint's navy paper, which nothing else draws under Paper.
card_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + ((.width - 1000) / 2 | floor) + 957),\(.y + 308) 10x10"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
card_is_navy() { local r g b; read -r r g b < <(card_rgb); ((r < 40 && g < 50 && b < 70 && b > r)); }
themes_shown() { state_is .open && themes_focus Exclusive && card_is_navy; }
# No pixel check here: after a switch to Blueprint its paper is the same navy as the card.
themes_gone() { state_is '.open == false' && themes_focus None; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
open_ms() {
  until_ok 3000 state_is ".opens == $1 and (.openMs | type) == \"number\"" || { echo "none"; return; }
  themes_state | jq -r .openMs
}

until_ok 5000 shell_status >/dev/null
until_ok 3000 status_theme paper

mod_shift_t
until_ok 3000 themes_shown
check "Mod+Shift+T shows the switcher with exclusive keyboard" themes_shown
check "state lists paper, artboard, blueprint with paper selected and current" \
  state_is '.open and .themes == ["paper","artboard","blueprint"] and .selected == "paper" and .current == "paper"'
ms1=$(open_ms 1)

wtype j
until_ok 1000 state_is '.selected == "artboard"'
check "j moves the cursor to artboard" state_is '.selected == "artboard"'
wtype j
until_ok 1000 state_is '.selected == "blueprint"'
check "j again moves it to blueprint" state_is '.selected == "blueprint"'

wtype -k Return
until_ok 2000 themes_gone
check "Enter closes the switcher and releases the keyboard" themes_gone
until_ok 1000 status_theme blueprint
check "shell status reports blueprint within 1 s" status_theme blueprint
check "the state file reads blueprint" test "$(cat "$XDG_STATE_HOME/dots/theme" 2>/dev/null)" = blueprint
switch=$XDG_STATE_HOME/dots/theme-switch.json
# dots theme writes this after its last reload, later than the state file.
until_ok 2000 jq -e '.to == "blueprint"' "$switch" >/dev/null 2>&1
check "theme-switch.json records paper to blueprint: $(cat "$switch" 2>/dev/null)" \
  bash -c "jq -e '.from == \"paper\" and .to == \"blueprint\" and .ms <= 300' '$switch' >/dev/null"

mod_shift_t
until_ok 3000 state_is '.open' && until_ok 3000 themes_focus Exclusive
check "reopening starts the cursor on blueprint" state_is '.open and .selected == "blueprint" and .current == "blueprint"'
ms2=$(open_ms 2)
wtype k
until_ok 1000 state_is '.selected == "artboard"'
check "k moves the cursor to artboard" state_is '.selected == "artboard"'
wtype -k Escape
until_ok 2000 themes_gone
check "Esc closes the switcher and releases the keyboard" themes_gone
sleep 0.5
check "Esc applies nothing, status still blueprint" status_theme blueprint

echo "     openMs: first $ms1, second $ms2"
check "the second open took ${ms2} ms, 16 or less" bash -c "[ '$ms2' != none ] && (( $ms2 <= 16 ))"

exit $((fails > 0))
