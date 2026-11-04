#!/usr/bin/env bash
# Mod+Shift+T opens the theme switcher, j/k move the cursor, Enter applies through dots colorscheme, Esc closes.
{
export DOTS_DEV_SCHEME=artboard
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_shift_t() { niri msg action spawn -- dots-call themes toggle; }
themes_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# Near the right edge of the Catppuccin Mocha card's preview, by the card's box in the switcher's state: its dark paper, which nothing else draws under Artboard.
card_rgb() {
  local geo
  geo=$(themes_state | jq -r 'first(.cards[] | select(.name == "catppuccin-mocha")).box | "\(.x + .w - 20 | floor),\(.y + 60 | floor) 10x10"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
card_is_dark() { local r g b; read -r r g b < <(card_rgb); ((r < 50 && g < 50 && b < 70 && b > r)); }
themes_shown() { state_is '.open and .settled' && themes_focus Exclusive && card_is_dark; }
# No pixel check here: after the switch the switcher is gone, and its state names where it drew.
themes_gone() { state_is '.open == false' && themes_focus None; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
open_ms() {
  until_ok 3000 state_is ".opens == $1 and (.openMs | type) == \"number\"" || { echo "none"; return; }
  themes_state | jq -r .openMs
}

until_ok 5000 shell_status >/dev/null
until_ok 3000 status_theme artboard

mod_shift_t
until_ok 3000 themes_shown
check "Mod+Shift+T shows the switcher with exclusive keyboard" themes_shown
check "state lists the five colorschemes with artboard selected and current" \
  state_is '.open and .themes == ["artboard","catppuccin-mocha","github-light","gruvbox-dark","rose-pine-dawn"] and .selected == "artboard" and .current == "artboard"'
ms1=$(open_ms 1)

wtype j
until_ok 1000 state_is '.selected == "catppuccin-mocha"'
check "j moves the cursor to catppuccin-mocha" state_is '.selected == "catppuccin-mocha"'
wtype j
until_ok 1000 state_is '.selected == "github-light"'
check "j again moves it to github-light" state_is '.selected == "github-light"'

wtype -k Return
until_ok 2000 themes_gone
check "Enter closes the switcher and releases the keyboard" themes_gone
until_ok 1000 status_theme github-light
check "shell status reports github-light within 1 s" status_theme github-light
check "the state file reads github-light" test "$(cat "$XDG_STATE_HOME/dots/theme" 2>/dev/null)" = github-light
switch=$XDG_STATE_HOME/dots/theme-switch.json
# dots colorscheme writes this after its last reload, later than the state file.
until_ok 2000 jq -e '.to == "github-light"' "$switch" >/dev/null 2>&1
check "theme-switch.json records artboard to github-light: $(cat "$switch" 2>/dev/null)" \
  bash -c "jq -e '.from == \"artboard\" and .to == \"github-light\" and .ms <= 300' '$switch' >/dev/null"

mod_shift_t
until_ok 3000 state_is '.open' && until_ok 3000 themes_focus Exclusive
check "reopening starts the cursor on github-light" state_is '.open and .selected == "github-light" and .current == "github-light"'
ms2=$(open_ms 2)
wtype k
until_ok 1000 state_is '.selected == "catppuccin-mocha"'
check "k moves the cursor to catppuccin-mocha" state_is '.selected == "catppuccin-mocha"'
wtype -k Escape
until_ok 2000 themes_gone
check "Esc closes the switcher and releases the keyboard" themes_gone
sleep 0.5
check "Esc applies nothing, status still github-light" status_theme github-light

# The launcher and the switcher draw in one Overlay window, and opening one closes the other.
launcher_is() { timeout 0.5 qs ipc call launcher state 2>/dev/null | jq -e "$1" >/dev/null; }
overlays() { niri msg -j layers | jq -c '[.[] | select(.layer == "Overlay") | .namespace]'; }
launcher_holds() { launcher_is .open && themes_focus Exclusive; }
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_holds
check "the launcher holds dots-surfaces' keyboard exclusive" launcher_holds
mod_shift_t
until_ok 3000 state_is .open
check "opening the switcher closes the launcher" launcher_is '.open == false'
check "niri lists one Overlay layer from the shell, dots-surfaces: $(overlays)" test "$(overlays)" = '["dots-surfaces"]'
wtype -k Escape
until_ok 2000 themes_gone
check "with both closed, dots-surfaces takes no keyboard" themes_gone

echo "     openMs: first $ms1, second $ms2"
check "the second open took ${ms2} ms, 16 or less" bash -c "[ '$ms2' != none ] && (( $ms2 <= 16 ))"

exit $((fails > 0))
}
