#!/usr/bin/env bash
# The island draws in dots-surfaces, the one Overlay window every surface draws in, on niri's focused output.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

layers() { niri msg -j layers; }
layer_up() { layers | jq -e --arg ns "$1" 'any(.[]; .namespace == $ns)' >/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$1" >/dev/null 2>&1; }

# The resting island is drawn in dots-surfaces, so the window maps with the margins, not on the surfaces' warm-up a second later.
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
until_ok 3000 eval '! layer_up dots-paper'
until_ok 10000 layer_up dots-margins
t_margins=$(now_ms)
until_ok 3000 layer_up dots-surfaces
gap=$(($(now_ms) - t_margins))
check "dots-surfaces maps with the margins, not a second later (${gap} ms)" test "$gap" -le 400
until_ok 5000 shell_status >/dev/null

focused=$(niri msg -j focused-output | jq -r .name)
once_on_focused() { layers | jq -e --arg o "$focused" '[.[] | select(.namespace == "dots-surfaces")] | length == 1 and .[0].output == $o' >/dev/null; }
check "dots-surfaces is listed once, on the focused output $focused" once_on_focused

check "no layer is named dots-island" eval '! layer_up dots-island'
until_ok 3000 island_is '.mode == "rest" and .shown'
surfaces_keys() { layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
check "at rest the island shows and dots-surfaces holds no keyboard" surfaces_keys None
check "at rest island state reads surface null, waiting 0 and takeover null ($(island | jq -c '{surface, waiting, takeover}'))" island_is '.surface == null and .waiting == 0 and .takeover == null'
timeout 0.5 qs ipc call island focus
until_ok 2000 surfaces_keys Exclusive
check "Mod+I gives the island the keyboard through dots-surfaces" surfaces_keys Exclusive
wtype -k Escape
until_ok 2000 surfaces_keys None
check "and Esc gives it back" surfaces_keys None

notify-send hi
until_ok 2000 island_is '.mode == "notification"'
note=$(island)
shows_hi() { jq -e '.text | test("hi")' <<<"$note" >/dev/null; }
check "notify-send hi shows hi in the island ($(jq -c '{mode, text}' <<<"$note"))" shows_hi
until_ok 8000 island_is '.mode == "rest"'
held=$(($(island | jq .since) - $(jq .since <<<"$note")))
check "the island is back to the clock after 5.0 ± 0.3 s (${held} ms)" test "$held" -ge 4700 -a "$held" -le 5300
until_ok 2000 eval 'shell_status | jq -e ".timers == 1" >/dev/null'
check "and the shell runs one timer ($(shell_status | jq .timers))" eval 'shell_status | jq -e ".timers == 1" >/dev/null'

# A floating foot under the island takes a click 100 px below it, though a tiled foot had the focus; niri reports a position for floating windows only.
focused() { niri msg -j focused-window | jq -r '.id // "none"'; }
foots() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
until_ok 2000 eval 'island_is ".animating == false"'
read -r cx below < <(timeout 0.5 qs ipc call island box island | jq -r '"\((.x + .w / 2) | floor) \((.y + .h + 100) | floor)"')
niri msg action spawn -- foot -c /dev/null
until_ok 5000 eval '[ "$(foots)" = 1 ]'
target=$(focused)
niri msg action toggle-window-floating
niri msg action move-floating-window --x "$((cx - 200))" --y "$((below - 60))"
niri msg action spawn -- foot -c /dev/null
until_ok 5000 eval '[ "$(foots)" = 2 ]'
other=$(focused)
covers() { niri msg -j windows | jq -e --argjson id "$target" --argjson x "$cx" --argjson y "$below" '.[] | select(.id == $id) | .layout as $l | $l.tile_pos_in_workspace_view[0] <= $x and $x < $l.tile_pos_in_workspace_view[0] + $l.tile_size[0] and $l.tile_pos_in_workspace_view[1] <= $y and $y < $l.tile_pos_in_workspace_view[1] + $l.tile_size[1]' >/dev/null; }
until_ok 2000 covers
check "the floating foot $target is drawn 100 px below the island, and the tiled foot $other has the focus" eval 'covers && [ "$(focused)" = "$other" ]'
point click "$cx" "$below"
until_ok 2000 eval '[ "$(focused)" = "$target" ]'
check "a click 100 px below the resting island focuses the foot drawn there (focus $(focused))" test "$(focused)" = "$target"

niri msg action fullscreen-window
until_ok 3000 island_is '.shown == false'
check "over a fullscreen window the island reads shown false" island_is '.shown == false'
niri msg action fullscreen-window
until_ok 3000 island_is '.shown'
exit "$fails"
}
