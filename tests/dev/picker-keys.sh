#!/usr/bin/env bash
# Digits jump the picker's cursor, the card it lands on plays its theme's switch in miniature, and only Enter changes the desktop.
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
until_ok 3000 status_theme paper
niri msg action spawn -- dots-call themes toggle
until_ok 3000 state_is '.open and .settled'
check "the picker opens with nothing played" state_is '.played == null'

wtype 3
until_ok 1000 played blueprint
check "3 puts the cursor on blueprint" state_is '.selected == "blueprint"'
check "the shell still reports paper" status_theme paper
check "blueprint's card played its scan in $(played_ms) ms, 260 or less" within 260

wtype 1
until_ok 1000 played paper
check "1 jumps back to paper, whose card slid up in $(played_ms) ms, 260 or less" within 260
was=$(themes_state | jq -c .played)
wtype 7
sleep 0.3
check "7, with no card, leaves the cursor on paper, not the last card, and plays nothing" \
  state_is --argjson was "$was" '.selected == "paper" and .played == $was'

wtype j
until_ok 1000 played artboard
check "j lands on artboard, whose card zoomed in $(played_ms) ms, 260 or less" within 260
check "the shell still reports paper after the moves" status_theme paper

wtype -k Return
until_ok 2000 state_is '.open == false'
until_ok 1000 status_theme artboard
check "Enter applies artboard and closes the picker" status_theme artboard

exit $((fails > 0))
}
