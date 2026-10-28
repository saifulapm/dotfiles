#!/usr/bin/env bash
# dots-pointer, built as apply builds it, lands exactly: a pick on a window's first column names it and one column left names nothing; a pick niri never answers exits 3 in about 500 ms and presses nothing.
{
source "$(dirname "$0")/lib.sh"

dots_pointer_build || exit 1
b=$DOTS_DEV_DIR/dots-pointer

box=$(niri msg -j outputs | jq -r '[.[] | .logical] | (map(.x) | min) as $x | (map(.y) | min) as $y | "\($x),\($y),\((map(.x + .width) | max) - $x),\((map(.y + .height) | max) - $y)"')
dp() { "$b/dots-pointer" "$box" "$@"; }
picked() { dp move "$1" "$2" pick | jq -c '.Ok.PickedWindow.id // null'; }
foots() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
focused() { niri msg -j focused-window | jq -r .id; }
foots_are() { [ "$(foots)" = "$1" ]; }
focus_is() { [ "$(focused)" = "$1" ]; }

# A floating foot moved to a known spot is the ground truth: niri reports where its tile is, and the tiled foot's quarter-width column ends far left of it.
niri msg action spawn -- foot -c /dev/null
until_ok 5000 foots_are 1
float=$(focused)
niri msg action toggle-window-floating --id "$float"
niri msg action move-floating-window --id "$float" -x 1600 -y 300
tile_at() { niri msg -j windows | jq -e ".[] | select(.id == $float) | .layout.tile_pos_in_workspace_view | map(floor) == [$1, $2]" >/dev/null; }
until_ok 3000 tile_at 1600 300
niri msg action spawn -- foot -c /dev/null
until_ok 5000 foots_are 2
tiled=$(niri msg -j windows | jq ".[] | select(.app_id == \"foot\" and .id != $float) | .id")
niri msg action focus-window --id "$tiled"
until_ok 2000 focus_is "$tiled"
niri msg action set-column-width 25%
sleep 0.5

check "a pick on the floating foot's first column names it" test "$(picked 1600 500)" = "$float"
check "and one column left of it names nothing" test "$(picked 1599 500)" = null
niri msg action focus-window --id "$tiled"
until_ok 2000 focus_is "$tiled"

# A socket that takes the request and never answers stands in for a niri that never installs the grab.
python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1]); s.listen(4)
held = []
while True:
    held.append(s.accept()[0])
' "$b/mute.sock" &
mute=$!
cleanup() { kill "$mute" 2>/dev/null; }
until_ok 2000 test -S "$b/mute.sock"
t0=$(now_ms)
NIRI_SOCKET=$b/mute.sock "$b/dots-pointer" "$box" move 1700 500 pick >/dev/null 2>&1
rc=$? ms=$(($(now_ms) - t0))
check "a pick niri never answers exits 3 (got $rc)" test "$rc" = 3
check "after about 500 ms (took $ms)" test "$ms" -ge 450 -a "$ms" -le 1200
sleep 0.3
check "and pressed nothing: the tiled foot keeps focus" focus_is "$tiled"
# The same pick against niri does press there, and niri focuses the window it names, so the check above can fail.
check "while a real pick there names the floating foot" test "$(picked 1700 500)" = "$float"
check "and moves focus onto it" until_ok 1000 focus_is "$float"

exit $((fails > 0))
}
