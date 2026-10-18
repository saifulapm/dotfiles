#!/usr/bin/env bash
# Notes is a real window docked right: Mod+N and Esc move focus, a pinned Notes stays while foot keeps its keyboard.
source "$(dirname "$0")/lib.sh"

notes_is() { timeout 0.5 qs ipc call notes state 2>/dev/null | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_n() { niri msg action spawn -- qs ipc call notes toggle; }
mod_shift_n() { niri msg action spawn -- qs ipc call notes pin; }
notes_window() { niri msg -j windows | jq -e '.[] | select(.title == "Notes")' 2>/dev/null; }
notes_listed() { notes_window >/dev/null; }
notes_gone() { ! notes_listed; }
notes_focused() { notes_window | jq -e '.is_focused' >/dev/null; }
focused_is() { niri msg -j windows | jq -e --argjson id "$1" 'any(.[]; .id == $id and .is_focused)' >/dev/null; }
# 420 px wide, its right edge one 32 px gap in from the focused output's.
docked_right() {
  local out
  out=$(niri msg -j focused-output | jq '.logical.width')
  notes_window | jq -e --argjson w "$out" '.is_floating and .layout.window_size[0] == 420 and (.layout.tile_pos_in_workspace_view[0] + .layout.tile_size[0] + 32 == $w)' >/dev/null
}

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
typed=$(mktemp -u)
cleanup() { rm -f "$typed"; }
niri msg action spawn -- foot -e sh -c "read x; echo \"\$x\" > $typed"
foot_up() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .is_focused)' >/dev/null; }
until_ok 5000 foot_up
foot=$(niri msg -j windows | jq '.[] | select(.app_id == "foot") | .id')

mod_n
until_ok 3000 notes_focused
check "Mod+N from foot shows and focuses Notes" notes_focused
check "niri lists Notes 420 px wide at the right edge of the focused output" docked_right
check "the composer has the keyboard" notes_is '.open and .mode == "composer"'
wtype -k Escape
until_ok 2000 focused_is "$foot"
check "Esc focuses the same foot window again" focused_is "$foot"
until_ok 2000 notes_gone
check "with Notes not pinned, Esc hides it" notes_gone

mod_n
until_ok 3000 notes_focused
wl-copy 'copied elsewhere'
wtype -M ctrl v -m ctrl
until_ok 2000 notes_is '.composer == "copied elsewhere"'
check "Ctrl+V in the composer pastes what another app copied" notes_is '.composer == "copied elsewhere"'
wtype -k Return
until_ok 2000 notes_is '.count == 1 and .composer == ""'
check "Enter saves the composer as a note" notes_is '.count == 1 and .notes[0].text == "copied elsewhere"'
mod_n
until_ok 2000 notes_gone
check "Mod+N on a focused Notes hides it" notes_gone
check "and focus is back on foot" focused_is "$foot"

mod_shift_n
until_ok 3000 notes_focused
check "Mod+Shift+N pins and shows Notes" notes_is '.open and .pinned'
wtype -k Escape
until_ok 2000 focused_is "$foot"
check "Esc on a pinned Notes focuses foot" focused_is "$foot"
check "and keeps Notes listed" notes_listed
mod_n
until_ok 3000 notes_focused
check "Mod+N from foot focuses the pinned Notes" notes_focused
wtype -k Escape
until_ok 2000 focused_is "$foot"
wtype 'echo ok'
wtype -k Return
typed_ok() { [ "$(cat "$typed" 2>/dev/null)" = "echo ok" ]; }
until_ok 3000 typed_ok
check "with Notes pinned, typing echo ok lands in foot" typed_ok
check "and nothing reached the composer" notes_is '.composer == ""'
niri msg action spawn -- qs ipc call notes pin
until_ok 2000 notes_is '.pinned | not'
niri msg action focus-window-previous
until_ok 2000 notes_gone
timeout 0.5 qs ipc call notes open
until_ok 3000 notes_focused
check "qs ipc call notes open shows and focuses Notes" notes_is '.open and .focused'

exit $((fails > 0))
