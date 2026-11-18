#!/usr/bin/env bash
# A typed prefix shows its mode as an inverted chip inside the field, Backspace on an empty field takes it out, Mod+V, Mod+. and Mod+Shift+T open with theirs, and windows and emoji draw flat rows with their own icon.
{
source "$(dirname "$0")/lib.sh"

launcher() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher | jq -e "$@" >/dev/null 2>&1; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }

until_ok 5000 shell_status >/dev/null

open_launcher
check "the field shows no chip in apps mode ($(launcher | jq -c .chip))" state_is '.chip == null'
for p in "w Windows" "v Clipboard" ": Emoji" "= Calculator" "> Commands" "r Remind" "c Colorschemes"; do
  key=${p%% *} name=${p#* }
  wtype -- "$key "
  until_ok 2000 state_is --arg n "$name" '.chip.name == $n'
  check "'$key ' shows the $name chip and leaves the field empty ($(launcher | jq -c '{chip, field: .field.text, query}'))" state_is --arg n "$name" --arg q "$key " '.chip.name == $n and .chip.inverted and .field.text == "" and .query == $q'
  wtype -k BackSpace
  until_ok 2000 state_is '.chip == null and .query == ""'
done
check "Backspace on an empty field takes the chip out" state_is '.chip == null and .query == ""'
wtype "= 2+2"
until_ok 2000 state_is '.query == "= 2+2"'
check "= 2+2 reads 2+2 in the field beside the Calculator chip ($(launcher | jq -c '{chip: .chip.name, field: .field.text}'))" state_is '.chip.name == "Calculator" and .field.text == "2+2"'
close_launcher

for p in "clipboard Clipboard v" "emoji Emoji :" "colorschemes Colorschemes c"; do
  read -r mode name key <<<"$p"
  niri msg action spawn -- dots-call launcher mode "$mode"
  until_ok 3000 state_is --arg n "$name" '.open and .chip.name == $n'
  check "dots-call launcher mode $mode opens with the $name chip in the field ($(launcher | jq -c '{chip: .chip.name, query}'))" state_is --arg n "$name" --arg q "$key " '.chip.name == $n and .query == $q and .field.text == ""'
  close_launcher
done

# A window titled with U+202E and a newline draws its title without them.
niri msg action spawn -- foot -c /dev/null -T "$(printf 'evil\u202etxt.exe')" sleep 60
until_ok 5000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"foot\")" >/dev/null'
open_launcher
wtype "w "
until_ok 3000 state_is '.mode == "windows" and (.results | length) >= 1'
check "windows draws flat 48 px rows with the app's icon ($(launcher | jq -c '{rowHeights, slots}'))" state_is '(.rowHeights | all(. == 48)) and (.slots[0] | test("^image://icon/foot"))'
check "a window titled with U+202E draws without it ($(launcher | jq -c '.drawn[0]'))" state_is '.drawn[0] == "eviltxt.exe"'
close_launcher

open_launcher
wtype ": smile"
until_ok 3000 state_is '.mode == "emoji" and (.results | length) >= 1'
check "emoji draws flat 48 px rows, the emoji as the row's icon ($(launcher | jq -c '{rowHeights: .rowHeights[:3], slots: .slots[:3]}'))" state_is '(.rowHeights | all(. == 48)) and (.slots[0] | test("^[^A-Za-z]"))'
close_launcher
exit "$fails"
}
