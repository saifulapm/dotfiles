#!/usr/bin/env bash
# Mod+C glides the resting clock into Control's big clock, drawn on every frame of the open; Mod+Space fades it out instead.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
control() { timeout 0.5 qs ipc call control state 2>/dev/null; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest
read -r ow _ < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')

niri msg action spawn -- dots-call control toggle
until_ok 3000 island_is '.surface == "control" and .animating == false and .morph.kind == "open"'
until_ok 2000 surfaces_focus Exclusive
clock=$(island | jq -c .morph.clock)
target=$(control | jq -c .clock.box)
echo "     $(jq length <<<"$clock") frames; first $(jq -c '.[0]' <<<"$clock"), last $(jq -c '.[-1]' <<<"$clock"); big clock $target"
check "the open recorded its frames" jq -e 'length >= 5' <<<"$clock"
check "the glide drew the clock on every frame of the open" jq -e 'all(.[0] == 1)' <<<"$clock"
check "the resting label was never drawn beside it" jq -e 'all(.[4] == 0)' <<<"$clock"
# The first frame's clock is the label's 13 px, centred on the output as the resting island is.
first_centred() { jq -e --argjson ow "$ow" --argjson w "$(control | jq .clock.box.w)" '.[0] as $f | ($f[1] + $w * $f[3] / 2 - $ow / 2 | fabs) <= 4 and ($f[3] - 0.382 | fabs) < 0.05' <<<"$clock"; }
check "it starts at the island's centre at the label's size" first_centred
last_on_target() { jq -e --argjson b "$target" '.[-1] as $f | ($f[1] - $b.x | fabs) <= 2 and ($f[2] + 0 - $b.y | fabs) <= 40 and ($f[3] - 1 | fabs) < 0.06' <<<"$clock"; }
check "and ends on the big clock's place at its size" last_on_target
moves_left() { jq -e '[.[] | .[1]] as $x | $x[-1] < $x[0]' <<<"$clock"; }
check "moving left from the centre" moves_left
check "the big clock shows once the glide lands ($(control | jq -c .clock))" bash -c "timeout 0.5 qs ipc call control state | jq -e '.clock.text | test(\"^[0-9]{2}:[0-9]{2}\$\")' >/dev/null"

wtype -k Escape
until_ok 3000 at_rest
sleep 0.3
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 island_is '.surface == "launcher" and .animating == false and .morph.kind == "open"'
clock=$(island | jq -c .morph.clock)
echo "     launcher: label opacity per frame $(jq -c '[.[] | .[4]]' <<<"$clock")"
check "opening the launcher draws no glide" jq -e 'all(.[0] == 0)' <<<"$clock"
fades() { jq -e '[.[] | .[4]] as $o | ($o | any(. > 0 and . < 1)) and $o[-1] == 0' <<<"$clock"; }
check "and fades the resting clock out" fades
# From the launcher straight into Control there is no resting clock to move.
dots-call control toggle >/dev/null
until_ok 3000 island_is '.surface == "control" and .animating == false'
clock=$(island | jq -c .morph.clock)
check "a switch from the launcher into Control draws no glide ($(jq -c '[.[] | .[0]]' <<<"$clock"))" jq -e 'all(.[0] == 0)' <<<"$clock"
wtype -k Escape
until_ok 3000 at_rest
exit "$fails"
}
