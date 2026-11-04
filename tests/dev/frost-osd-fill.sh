#!/usr/bin/env bash
# Slowed 20 times, Frost's volume fill grows over 3.2 s: half-way it is partly drawn, and at rest it is 62 % of the track.
{
export DOTS_MOTION_SLOWDOWN=20
source "$(dirname "$0")/lib.sh"

has() { jq -e "$@" >/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | has --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
status_theme() { shell_status | has --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
# The OSD shows value $1 with its fill grown to that share of the track.
filled_to() { island | has --arg v "$1" '.mode == "osd" and .osd.value == $v and .osd.track != null and ((.osd.track.fill.w - .osd.track.box.w * ($v | tonumber) / 100) | fabs) < 1' >/dev/null 2>&1; }

until_ok 5000 shell_status >/dev/null
"$repo/bin/dots" theme frost >/dev/null
until_ok 10000 status_theme frost

until_ok 3000 mode_is rest
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 8000 filled_to 40
until_ok 40000 mode_is rest

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.62
start=$(now_ms)
# Half of the 3.2 s fill.
while (($(now_ms) - start < 1600)); do sleep 0.01; done
half=$(island | jq -c '.osd.track | (.fill.w / .box.w)')
echo "     half-way the fill is $half of the track"
check "half-way the fill is between 0.41 and 0.61 of the track ($half)" has '. > 0.41 and . < 0.61' <<<"$half"

until_ok 8000 filled_to 62
state=$(island)
echo "     osd: $(jq -c '[.osd.value, .osd.fillAnimation, .osd.track]' <<<"$state")"
check "the state reports a 3200 ms fill" has '.osd.fillAnimation.ms == 3200' <<<"$state"
check "at rest the fill is 62 % of the track within 1 px" has '((.osd.track.fill.w - .osd.track.box.w * 0.62) | fabs) < 1' <<<"$state"

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 40000 mode_is rest
errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"
exit $((fails > 0))
}
