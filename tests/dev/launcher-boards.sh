#!/usr/bin/env bash
# Each launcher mode draws its board 3 form in the island: the calculator's 40 px answer, a reminder's one tile, the clipboard's 2 x 2 preview cards, the colorschemes' cards three to a row, the commands in two columns.
{
source "$(dirname "$0")/lib.sh"

launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }

until_ok 5000 shell_status >/dev/null

open_launcher
wtype "= 2+2"
until_ok 3000 state_is '.answer.text == "4"'
check "= 2+2 draws the Calculator chip and 4 at 40 px bold with 2+2 under it ($(launcher | jq -c '{chip: .chip.name, answer, kinds}'))" state_is '.chip.name == "Calculator" and .answer == {text: "4", size: 40, bold: true, under: "2+2"} and .kinds == ["answer"] and .rowHeights == [80] and .filled == [false]'
wtype -k Return
until_ok 2000 state_is '.open == false'
copied() { [ "$(wl-paste -n 2>/dev/null)" = 4 ]; }
until_ok 2000 copied
check "Enter puts 4 on the clipboard ($(wl-paste -n 2>/dev/null))" copied

open_launcher
wtype "r 1m tea"
until_ok 3000 state_is '.results[0] == "tea"'
check "r 1m tea draws one 56 px filled tile reading tea with the time it rings ($(launcher | jq -c '{kinds, results, notes, rowHeights, filled}'))" state_is '.kinds[0] == "tile" and .results[0] == "tea" and (.notes[0] | test("[0-9]{2}:[0-9]{2}")) and .rowHeights[0] == 56 and .filled[0] == true and ([.kinds[] | select(. == "tile")] | length) == 1'
close_launcher

# Four clips, oldest first: a 100 KB text, an image, a colour and a short text.
clip() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" "$@"; }
more_than() { [ "$(clip list 2>/dev/null | wc -l)" -gt "$1" ]; }
n=$(clip list 2>/dev/null | wc -l)
head -c 100000 /dev/zero | tr '\0' x | wl-copy
until_ok 3000 more_than "$n"
wl-copy -t image/png <"$repo/dev/dekho/still.png"
until_ok 3000 more_than $((n + 1))
wl-copy '#C8381E'
until_ok 3000 more_than $((n + 2))
wl-copy 'just bench --only morph'
until_ok 3000 more_than $((n + 3))
niri msg action spawn -- dots-call launcher mode clipboard
until_ok 3000 state_is '.open and .mode == "clipboard" and (.clips | length) == 4 and .settled'
until_ok 3000 state_is '.clips[2].thumb'
check "Mod+V draws the clips as 2 x 2 cards of 84 px, each with its age ($(launcher | jq -c '{columns, clips: [.clips[] | {height, age}]}'))" state_is '.columns == 2 and (.clips | length) == 4 and (.clips | all(.height == 84 and .age == "now"))'
check "the image clip shows a thumbnail ($(launcher | jq -c '.clips[2] | {text, thumb}'))" state_is '.clips[2].thumb == true'
check "the colour clip shows its swatch ($(launcher | jq -c '.clips[1].swatch'))" state_is '.clips[1].swatch == "#c8381e"'
check "the 100 KB clip draws as a card cut to its box, three lines at most ($(launcher | jq -c '.clips[3] | {height, textHeight, lines}'))" state_is '.clips[3].height == 84 and .clips[3].textHeight <= 51 and .clips[3].lines <= 3'
close_launcher

read -r oh < <(niri msg -j outputs | jq -r '.[] | .logical.height')
island_h() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .height; }
open_launcher
wtype "c moc"
until_ok 3000 state_is '.results[0] == "Catppuccin Mocha"'
check "c moc draws scheme cards three to a row, 110 px tall ($(launcher | jq -c '{columns, rowHeights}'))" state_is '.columns == 3 and (.rowHeights | all(. == 110))'
check "Catppuccin Mocha's card shows its paper, surface and five dots ($(launcher | jq -c '.strips[0]'))" state_is '.strips[0] == ["#11111b","#1e1e2e","#89b4fa","#f38ba8","#a6e3a1","#f9e2af","#f5c2e7"]'
check "and no check, since Artboard is the current scheme ($(launcher | jq -c .checks))" state_is '.checks[0] == false'
t0=$(now_ms)
wtype -k Return
switched() { shell_status | jq -e '.theme == "catppuccin-mocha"' >/dev/null; }
until_ok 3000 switched
took=$(($(now_ms) - t0))
check "Enter switches to Catppuccin Mocha within 1 s (${took} ms)" test "$took" -le 1000

open_launcher
wtype "c "
until_ok 3000 state_is '.count == 40'
check "the current scheme's card has the check ($(launcher | jq -c '[.results, .checks] | transpose | map(select(.[1]))'))" state_is '[.results, .checks] | transpose | map(select(.[1])) | length <= 1'
wtype -k Tab
tallest=0
for _ in $(seq 39); do
  wtype j
  h=$(island_h)
  ((h > tallest)) && tallest=$h
done
until_ok 2000 state_is '.top + .selected == 39'
check "39 presses of j reach the 40th scheme card ($(launcher | jq -c '{top, selected, cursorName}'))" state_is '.top + .selected == 39 and .cursorName == .results[.selected]'
check "and the island's height stays at or under the output's less 48 px ($tallest, cap $((oh - 48)))" test "$tallest" -le $((oh - 48))
close_launcher

open_launcher
wtype "> "
until_ok 3000 state_is '.mode == "commands" and (.results | length) == 8'
same_rows() { launcher | jq -e '(.cursorBox.w) as $w | .columns == 2 and (.rowHeights | all(. == 48))' >/dev/null; }
check "> draws the commands as 48 px rows in two columns ($(launcher | jq -c '{columns, results}'))" same_rows
check "each draws its own glyph in a circle, not a letter ($(launcher | jq -c .slots))" state_is '(.slots | all(test("^[A-Za-z>]") | not))'
close_launcher
exit "$fails"
}
