#!/usr/bin/env bash
# A click outside an open surface closes it as Escape does, and the window that had focus has it again; a click on the card itself keeps the surface open.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$@" >/dev/null 2>&1; }
control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
control_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
layer_keys() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
focused() { niri msg -j focused-window | jq -r '.id // "none"'; }
foot_focused() { [ "$(focused)" = "$foot" ]; }
# A point on the card's own fill, clear of any row: 10 px in from its top left corner.
card_spot() { jq -r '.cardBox | "\(.x + 10 | floor) \(.y + 10 | floor)"'; }

until_ok 5000 shell_status >/dev/null

niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .settled'
until_ok 2000 layer_keys Exclusive
# shellcheck disable=SC2046
point click $(launcher_state | card_spot)
sleep 0.3
check "a click on the launcher's card keeps it open" launcher_is '.open'
point click 40 $((oh - 40))
until_ok 2000 launcher_is '.open == false'
check "a click on the paper closes the launcher" launcher_is '.open == false'
until_ok 2000 layer_keys None
check "and gives the keyboard back" layer_keys None

niri msg action spawn -- foot -c /dev/null
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
foot=$(focused)
check "a foot opens with the focus ($foot)" test "$foot" != none

niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .settled'
until_ok 2000 layer_keys Exclusive
point click $((ow - 40)) $((oh - 40))
until_ok 2000 launcher_is '.open == false'
check "a click outside the launcher closes it over a window" launcher_is '.open == false'
until_ok 2000 foot_focused
check "and the window that had focus keeps it ($(focused))" foot_focused

niri msg action spawn -- dots-call control toggle
until_ok 3000 control_is '.open and .settled'
until_ok 2000 layer_keys Exclusive
check "with Control open the foot holds no keyboard ($(focused))" test "$(focused)" = none
point click 40 $((oh / 2))
until_ok 2000 control_is '.open == false'
check "a click on the foot closes Control" control_is '.open == false'
until_ok 2000 foot_focused
check "and focuses that foot ($(focused))" foot_focused

exit "$fails"
}
