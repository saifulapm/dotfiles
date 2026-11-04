#!/usr/bin/env bash
# Slowed 20 times, the frost switch runs 5.6 s: at its 180 ms point the frost covers the middle, from Blueprint as much as from Paper of the screen, the paper is static once it ends, and a switch asked for mid-frost ends on the last theme.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null

status_at_rest() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
started_after() { (($(shell_status | jq -r '.transitionStartedAt') > $1)); }
read -r ox oy w h < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y) \(.width) \(.height)"')
centre="$((ox + w / 2 - 200)),$((oy + h / 2 - 150)) 400x300"
# Clear of the passage centred on the desk, as frost-paper.sh reads Frost's clear middle.
clear="$((ox + w / 2 - 200)),$((oy + h / 10)) 400x300"
# The paper below the bar and the island, whose clock may tick between two grabs.
lower="$ox,$((oy + h / 4)) ${w}x$((h * 3 / 4))"

# From Blueprint, whose navy is darker than Frost's paper, so only the frost can brighten the middle.
"$repo/bin/dots" theme blueprint >/dev/null
until_ok 10000 status_at_rest blueprint
sleep 1

# Just past the 180 ms point, timed from the shell's own start stamp, so Frost's dark paper is already under the frost; the polls before it only find the stamp.
before=$(now_ms)
"$repo/bin/dots" theme frost >/dev/null &
pid=$!
until_ok 3000 started_after "$before"
began=$(shell_status | jq -r '.transitionStartedAt')
while (($(now_ms) - began < 3630)); do sleep 0.01; done
covered=$(grim -s 1 -t ppm -g "$centre" - | mean_rgb)
# At 250 ms the frost has melted off the middle, which shows the theme swapped in under it, not Blueprint's navy.
while (($(now_ms) - began < 250 * 20)); do sleep 0.01; done
melted=$(grim -s 1 -t ppm -g "$clear" - | mean_rgb)
wait "$pid"
brighter() { local r g b; read -r r g b <<<"$1"; ((r >= 46 + 60 && g >= 52 + 60 && b >= 64 + 60)); }
check "just past the 180 ms point the centre 400 x 300 ($covered) is brighter than #2E3440 by 60 on each channel" brighter "$covered"
near_frost() { local r g b; read -r r g b <<<"$1"; ((r - 46 <= 8 && 46 - r <= 8 && g - 52 <= 8 && 52 - g <= 8 && b - 64 <= 8 && 64 - b <= 8)); }
check "at 250 ms the melted middle ($melted) is Frost's paper, swapped in under the frost" near_frost "$melted"

until_ok 8000 status_at_rest frost
sleep 2
a=$(mktemp) b=$(mktemp)
grim -s 1 -t ppm -g "$lower" "$a"
sleep 2
grim -s 1 -t ppm -g "$lower" "$b"
check "2 s after the switch ends, two grims 2 s apart are identical" cmp -s "$a" "$b"
rest=$(grim -s 1 -t ppm -g "$clear" - | mean_rgb)
near_paper() { local r g b; read -r r g b <<<"$1"; ((r - 46 <= 2 && 46 - r <= 2 && g - 52 <= 2 && 52 - g <= 2 && b - 64 <= 2 && 64 - b <= 2)); }
check "after the switch the middle ($rest) is Frost's clear paper #2E3440" near_paper "$rest"

# Blueprint asked for 1 s into the growth out of Frost, then Paper 1 s later: it ends on Paper and rests.
"$repo/bin/dots" theme blueprint >/dev/null
sleep 1
"$repo/bin/dots" theme paper >/dev/null
until_ok 15000 status_at_rest paper
check "a switch asked for mid-frost ends on the last theme asked for, paper" test "$(shell_status | jq -r .theme)" = paper
sleep 2
grim -s 1 -t ppm -g "$lower" "$a"
sleep 2
grim -s 1 -t ppm -g "$lower" "$b"
check "after it, two grims 2 s apart are identical" cmp -s "$a" "$b"
cream() { local r g b; read -r r g b <<<"$1"; ((r > 200 && g > 200 && b > 180)); }
ended=$(grim -s 1 -t ppm -g "$centre" - | mean_rgb)
check "the centre ($ended) is Paper's cream" cream "$ended"

# Blueprint asked for past the swap of a frost switch into Frost: the frost switch out of Frost plays from what is on screen and ends on Blueprint at rest.
before=$(now_ms)
"$repo/bin/dots" theme frost >/dev/null &
pid=$!
until_ok 3000 started_after "$before"
began=$(shell_status | jq -r '.transitionStartedAt')
wait "$pid"
while (($(now_ms) - began < 200 * 20)); do sleep 0.01; done
"$repo/bin/dots" theme blueprint >/dev/null
until_ok 15000 status_at_rest blueprint
check "a switch asked for past the swap ends on the last theme asked for, blueprint" test "$(shell_status | jq -r .theme)" = blueprint
sleep 2
grim -s 1 -t ppm -g "$lower" "$a"
sleep 2
grim -s 1 -t ppm -g "$lower" "$b"
check "after it, two grims 2 s apart are identical" cmp -s "$a" "$b"
navy=$(grim -s 1 -t ppm -g "$clear" - | mean_rgb)
is_navy() { local r g b; read -r r g b <<<"$1"; ((r < 30 && g < 40 && b > 35 && b < 70)); }
check "the middle ($navy) is Blueprint's navy" is_navy "$navy"
rm -f "$a" "$b"

timers_one() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "after the switches status reports timers 1" timers_one

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb|Paper.qml')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
