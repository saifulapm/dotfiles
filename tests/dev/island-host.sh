#!/usr/bin/env bash
# The island draws in dots-surfaces, the one Overlay window every surface draws in, on niri's focused output.
{
source "$(dirname "$0")/lib.sh"

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
exit
}
