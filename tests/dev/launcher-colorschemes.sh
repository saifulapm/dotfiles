#!/usr/bin/env bash
# The launcher's c mode: c and a space list every colorscheme, typing filters by title and family, the selection scrolls past the eighth row, Enter switches within 1000 ms of the key, and Mod+Shift+T opens the same list where the Themes surface was.
{
export DOTS_DEV_SCHEME=artboard
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
schemes=$(ls "$repo"/colorschemes/*.toml | wc -l)

until_ok 5000 shell_status >/dev/null

open_launcher
wtype "c"
until_ok 2000 state_is '.query == "c"'
check "c without its space stays an app search" state_is '.mode == "apps"'
wtype " "
until_ok 3000 state_is '.mode == "colorschemes" and .count > 0'
check "c and a space list all $schemes colorschemes ($(launcher_state | jq .count))" state_is ".mode == \"colorschemes\" and .count == $schemes and .count == 40"
check "eight rows show, Artboard first" state_is '(.results | length) == 8 and .results[0] == "Artboard"'
check "under artboard the artboard row carries the mark and no other row does" state_is '.marks[0] == true and ([.marks[] | select(.)] | length) == 1'
artboard_strip='["#e4e6ea","#ffffff","#3d5afe","#cf222e","#1a7f37","#9a6700","#8250df"]'
check "the artboard row draws paper, surface, accent and ANSI 1, 2, 3 and 5" state_is ".strips[0] == $artboard_strip"
for _ in $(seq 1 10); do wtype -M ctrl -k j -m ctrl; done
until_ok 2000 state_is '.top + .selected == 10'
check "ten moves down scroll the list: the tenth row below the first is lit and drawn ($(launcher_state | jq -c '{top, selected}'))" state_is '.top == 3 and .selected == 7 and (.results | length) == 8 and .cursorName == .results[7]'
for _ in $(seq 1 10); do wtype -M ctrl -k k -m ctrl; done
until_ok 2000 state_is '.top + .selected == 0'
check "ten moves up bring Artboard back to the top" state_is '.top == 0 and .selected == 0 and .cursorName == "Artboard"'
wtype "rose"
until_ok 2000 state_is '.query == "c rose"'
check "c rose leaves the three Rosé Pine rows ($(launcher_state | jq -c .results))" state_is '.results == ["Rosé Pine", "Rosé Pine Dawn", "Rosé Pine Moon"]'
close_launcher

open_launcher
wtype "c moc"
until_ok 2000 state_is '.query == "c moc"'
check "c moc leaves Catppuccin Mocha alone" state_is '.results == ["Catppuccin Mocha"] and .count == 1'
record=$XDG_STATE_HOME/dots/theme-switch.json
rm -f "$record"
key=$(now_ms)
wtype -k Return
until_ok 3000 test -s "$record"
check "Enter saves catppuccin-mocha" test "$(cat "$XDG_STATE_HOME/dots/theme")" = catppuccin-mocha
record_is() { jq -e --argjson k "$key" "$1" "$record" >/dev/null; }
check "the switch record starts at the key and ends within 1000 ms of it ($(jq -c --argjson k "$key" '{start: (.start - $k), end: (.end - $k)}' "$record"))" \
  record_is '.to == "catppuccin-mocha" and .start >= $k and .end - $k <= 1000'
until_ok 3000 eval "shell_status | jq -e '.theme == \"catppuccin-mocha\" and .transition == \"\"' >/dev/null"

# Mod+Shift+T's command, spawned through niri as the bind spawns it.
niri msg action spawn -- dots-call launcher mode colorschemes
until_ok 3000 state_is '.open and .keyboard and .settled'
check "Mod+Shift+T opens the launcher with c and a space typed" state_is '.query == "c " and .mode == "colorschemes" and .count == 40'
check "the mark moves to Catppuccin Mocha" state_is '[.results, .marks] | transpose | map(select(.[1])) == [["Catppuccin Mocha", true]]'
close_launcher

# The Themes surface is gone: no IPC target answers to it and the shell never loads it.
dots-call themes toggle 2>/dev/null
rc=$?
check "dots-call themes toggle exits 1 (got $rc)" test "$rc" = 1
check "the shell loads no themes surface" eval "shell_status | jq -e '.loaded | index(\"themes\") == null' >/dev/null"

exit $((fails > 0))
}
