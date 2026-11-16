#!/usr/bin/env bash
# The island opens and closes with the approved motion: one spring progress for the box in a window that never resizes, content laid out at its target width from the first frame, and an open mid-close that turns back from where the box is.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
sheet() { timeout 0.5 qs ipc call cheatsheet state 2>/dev/null; }
at_rest() { island_is '.surface == null and .width == 176 and .animating == false'; }
settled_open() { island_is '.surface == "cheatsheet" and .animating == false'; }

until_ok 5000 shell_status >/dev/null
until_ok 3000 at_rest
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')

dots-call cheatsheet toggle >/dev/null
until_ok 3000 settled_open
open_ms=$(($(island | jq .settledAt) - $(sheet | jq .openedAt)))
check "after Mod+/ the island reads animating false within 450 ms (${open_ms} ms)" test "$open_ms" -le 450
frames=$(island | jq -c .morph)
echo "     open: $(jq -c '{kind, from, n: (.frames | length), last: .frames[-1]}' <<<"$frames")"
one_window() { jq -e --argjson w "$ow" --argjson h "$oh" '.frames | length > 3 and all(.[]; .[3] == $w and .[4] == $h)' <<<"$frames" >/dev/null; }
check "the window stays ${ow} x ${oh} on every frame of the open" one_window
check "a row is drawn at its final width from the open's first frame ($(sheet | jq -c '{openRowWidth, now: .columns[0].rows[0].width}'))" eval 'sheet | jq -e ".openRowWidth != null and .openRowWidth == .columns[0].rows[0].width" >/dev/null'
overshoots() { jq -e '[.frames[][1]] | max > 1160' <<<"$frames" >/dev/null; }
check "the box overshoots its 1160 px on the spring ($(jq -c '[.frames[][1]] | max' <<<"$frames"))" overshoots

wtype -k Escape
until_ok 2000 at_rest
close_ms=$(($(island | jq .settledAt) - $(sheet | jq .closedAt)))
check "after Esc the island reads animating false within 200 ms (${close_ms} ms)" test "$close_ms" -le 200
frames=$(island | jq -c .morph)
check "the window stays ${ow} x ${oh} on every frame of the close" one_window

# An open 60 ms into the close turns back from where the box is drawn, never from the resting 176 px.
dots-call cheatsheet toggle >/dev/null
until_ok 3000 settled_open
wtype -k Escape
sleep 0.06
dots-call cheatsheet toggle >/dev/null
until_ok 3000 settled_open
frames=$(island | jq -c .morph)
echo "     reopen: $(jq -c '{kind, from, first: .frames[0]}' <<<"$frames")"
turned_back() { jq -e '.kind == "open" and .from[0] > 176 and .from[0] < 1160 and (.frames[0][1] - .from[0] | if . < 0 then -. else . end) < 60' <<<"$frames" >/dev/null; }
check "Mod+/ 60 ms into the close opens from where the box is, with no jump to rest" turned_back
exit "$fails"
}
