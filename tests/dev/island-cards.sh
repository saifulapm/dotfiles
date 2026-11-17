#!/usr/bin/env bash
# Board 2's cards: an icon circle, a bold title and a muted detail with the clock at the right, and the actions as buttons, the first inverted, with no number drawn; keys 1-9 still pick.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
settled() { until_ok "${2:-3000}" island_is "$1 and .animating == false"; }
mod_i() { niri msg action spawn -- dots-call island focus; }
# One output pixel as #RRGGBB.
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n' | tr a-f A-F | sed 's/^/#/'; }
answers=$(mktemp)
cleanup() { rm -f "$answers"; }

until_ok 3000 island_is '.mode == "rest"'
notify-send -A yes=Yes -A no=No "Deploy?" >"$answers" &
settled '.mode == "notification"'
echo "     note: $(island | jq -c '.note | {summary, app, age, buttons}')"
check "the card is 440 px wide ($(island | jq .width))" island_is '.width == 440'
check "its header reads Deploy? with the clock at the right" island_is --arg c "$(date +%H:%M)" '.note.summary == "Deploy?" and .note.age == $c and .note.clockRight == 0 and .note.summaryFont[1] == 15'
check "its buttons are Yes, inverted, and No, quiet, with no digit beside either" island_is '[.note.buttons[] | [.text, .primary]] == [["Yes", true], ["No", false]] and .note.buttons[0].fill != .note.buttons[1].fill'
read -r yx yy yw yh < <(island | jq -r '.note.actionBoxes[0] | "\(.x | floor) \(.y | floor) \(.w | floor) \(.h | floor)"')
read -r nx ny < <(island | jq -r '.note.actionBoxes[1] | "\(.x | floor) \(.y | floor)"')
yes_px=$(px $((yx + 6)) $((yy + yh / 2)))
no_px=$(px $((nx + 6)) $((ny + yh / 2)))
on=$(island | jq -r '.note.buttons[0].fill | ascii_upcase')
check "Yes is filled with the on colour $on ($yes_px) and No is not ($no_px)" test "$yes_px" = "$on" -a "$no_px" != "$on"
mod_i
until_ok 2000 island_is '.focused'
wtype 2
until_ok 3000 grep -qx no "$answers"
check "Mod+I then 2 answers no ($(cat "$answers"))" grep -qx no "$answers"
until_ok 3000 island_is '.mode == "rest"'

notify-send hi
settled '.mode == "notification"'
check "notify-send hi draws a card with no button row" island_is '.note.summary == "hi" and .note.buttons == [] and .note.actions == []'
mod_i
until_ok 2000 island_is '.focused'
wtype -k Escape
check "and it still closes on Esc" until_ok 2000 island_is '.mode == "rest"'

t0=$(now_ms)
notify-send "burst 1"
notify-send "burst 2"
notify-send "burst 3"
burst_ms=$(($(now_ms) - t0))
wait_burst() { island_is '.mode == "notification" and .note.summary == "burst 3"'; }
until_ok 3000 wait_burst
widths=()
for _ in 1 2 3 4 5; do widths+=("$(island | jq .drawn)"); sleep 0.05; done
check "three notifications in $burst_ms ms swap in place: the card stays 440 px (${widths[*]}) and ends on the third" bash -c "[ \"$(printf '%s\n' "${widths[@]}" | sort -u)\" = 440 ] && timeout 0.5 qs ipc call island state | jq -e '.note.summary == \"burst 3\" and .width == 440' >/dev/null"
exit "$fails"
}
