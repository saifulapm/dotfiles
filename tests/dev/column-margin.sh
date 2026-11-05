#!/usr/bin/env bash
# The top-left margin reads the focused column of the shown workspace's columns, follows a column move and drops it at one column.
{
source "$(dirname "$0")/lib.sh"

left_is() { timeout 0.5 qs ipc call margins state 2>/dev/null | jq -e --arg want "$1" '.drawn.left | startswith($want)' >/dev/null 2>&1; }
focused_is() { niri msg -j focused-window | jq -e --arg t "$1" '.title == $t' >/dev/null 2>&1; }
plain() { niri msg action spawn -- foot -c /dev/null -T "$1" sleep 600; until_ok 5000 focused_is "$1"; }

until_ok 5000 shell_status >/dev/null
plain one
check "one column draws no column" until_ok 2000 left_is "Page 01 / foot — one"
plain two
plain three
check "three foots, the third focused, read Page 01  3 / 3" until_ok 2000 left_is "Page 01  3 / 3 / foot — three"
niri msg action focus-column-left
check "focusing a column left reads Page 01  2 / 3" until_ok 2000 left_is "Page 01  2 / 3 / foot — two"
niri msg action move-column-left
check "moving that column left reads Page 01  1 / 3" until_ok 2000 left_is "Page 01  1 / 3 / foot — two"
niri msg action close-window
check "closing the first column leaves the focus on 1 / 2" until_ok 2000 left_is "Page 01  1 / 2 / foot — "
echo "     drawn: $(timeout 0.5 qs ipc call margins state | jq -c .drawn.left)"

exit $((fails > 0))
}
