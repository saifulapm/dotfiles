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

# A click on the island while a card is open is a click outside that card: it closes it, and the island opens nothing; the launcher and Control draw inside the island, so it is Goals' card here.
island_is() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
goals_is() { timeout 0.5 qs ipc call goals state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
timeout 0.5 qs ipc call goals open >/dev/null
until_ok 3000 goals_is '.open'
until_ok 2000 layer_keys Exclusive
read -r ix iy < <(timeout 0.5 qs ipc call island box island | jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"')
point click "$ix" "$iy"
until_ok 2000 goals_is '.open == false'
check "a click on the island closes open Goals as a click outside" goals_is '.open == false'
check "and the island opens no calendar ($(timeout 0.5 qs ipc call island state | jq -c '{mode, focused}'))" island_is '.mode == "rest" and .focused == false'
until_ok 2000 layer_keys None

# The notification centre closes on a click outside and keeps its history.
notifs_is() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
notify-send kept
until_ok 3000 notifs_is '.count >= 1'
count=$(timeout 0.5 qs ipc call notifs state | jq .count)
niri msg action spawn -- dots-call notifs toggle
until_ok 3000 notifs_is '.open'
until_ok 2000 layer_keys Exclusive
point click 40 $((oh - 40))
until_ok 2000 notifs_is '.open == false'
check "a click outside closes the notification centre" notifs_is '.open == false'
check "and deletes nothing from its history ($count before, $(timeout 0.5 qs ipc call notifs state | jq .count) after)" notifs_is --argjson n "$count" '.count == $n'
until_ok 2000 layer_keys None

# The file picker answers its asker when a click outside closes it, so the asking app never hangs.
answer=$DOTS_DEV_DIR/picker-answer
request=$(jq -cn --arg f "$HOME" '{mode: "open", multiple: false, title: "", app: "", folder: $f, name: "", filters: [], filter: 0, accept: ""}')
{ printf '%s\n' "$request"; sleep 8; } | socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/dots-picker-$WAYLAND_DISPLAY.sock" >"$answer" 2>/dev/null &
picker_is() { timeout 0.5 dots-call picker state 2>/dev/null | jq -e "$@" >/dev/null 2>&1; }
until_ok 4000 picker_is '.open'
point click 40 $((oh - 40))
until_ok 2000 picker_is '.open == false'
check "a click outside closes the file picker" picker_is '.open == false'
check "and the picker answers its asker ($(cat "$answer"))" until_ok 2000 grep -q '"response"' "$answer"

exit "$fails"
}
