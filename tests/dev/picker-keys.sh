#!/usr/bin/env bash
# Digits jump the picker's cursor, the card it lands on plays the crossfade in miniature, and only Enter changes the desktop.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

themes_state() { timeout 0.5 qs ipc call themes state 2>/dev/null; }
state_is() { themes_state | jq -e "$@" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
played() { state_is --arg n "$1" '.played.name == $n and .played.ms >= 0'; }
played_ms() { themes_state | jq -r .played.ms; }
# -1 means the play never finished.
within() { local ms; ms=$(played_ms); [ "$ms" != null ] && ((ms >= 0 && ms <= $1)); }

until_ok 5000 shell_status >/dev/null
until_ok 3000 status_theme artboard
niri msg action spawn -- dots-call themes toggle
until_ok 3000 state_is '.open and .settled'
check "the picker opens with nothing played" state_is '.played == null'

# The 260 ms crossfade reads a frame or so over between its own start and end stamps.
wtype 3
until_ok 1000 played github-light
check "3 puts the cursor on github-light" state_is '.selected == "github-light"'
check "the shell still reports artboard" status_theme artboard
check "github-light's card played its crossfade in $(played_ms) ms, 300 or less" within 300

wtype 1
until_ok 1000 played artboard
check "1 jumps back to artboard, whose card faded in in $(played_ms) ms, 300 or less" within 300
was=$(themes_state | jq -c .played)
wtype 7
sleep 0.3
check "7, with no card, leaves the cursor on artboard, not the last card, and plays nothing" \
  state_is --argjson was "$was" '.selected == "artboard" and .played == $was'

wtype j
until_ok 1000 played catppuccin-mocha
check "j lands on catppuccin-mocha, whose card faded in in $(played_ms) ms, 300 or less" within 300
check "the shell still reports artboard after the moves" status_theme artboard

wtype -k Return
until_ok 2000 state_is '.open == false'
until_ok 1000 status_theme catppuccin-mocha
check "Enter applies catppuccin-mocha and closes the picker" status_theme catppuccin-mocha

exit $((fails > 0))
}
