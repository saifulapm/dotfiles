#!/usr/bin/env bash
# In Frost the volume OSD is a 320 x 52 glass bar with a thin track filled in the accent; the brightness OSD keeps the bar.
{
fake=$(mktemp -d)
cat >"$fake/brightnessctl" <<EOF
#!/usr/bin/env bash
echo "fake-bl,backlight,\${3%\%},\$3,100"
EOF
chmod +x "$fake/brightnessctl"
# bin/dots-dev hands this PATH to the shell, so the shell runs the fake and never the real backlight.
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
state_has() { jq -e "$1" <<<"$state" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
# The OSD settled on value $1 with its fill grown to that share of the track (the fill eases in over 160 ms).
filled_to() { island | jq -e --arg v "$1" '.mode == "osd" and .animating == false and .osd.value == $v and .osd.track != null and ((.osd.track.fill.w - .osd.track.box.w * ($v | tonumber) / 100) | fabs) < 1' >/dev/null 2>&1; }
# Mean colour of the box at jq path $1, shrunk to a 4 x 4 patch at its fraction $2 along its width (or at its middle row for a box with a height of 6).
patch() {
  local geo
  geo=$(jq -r "$1 | \"\(.x + .w * $2 - 2 | floor),\(.y + .h / 2 - 2 | floor) 4x4\"" <<<"$state")
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }

until_ok 5000 shell_status >/dev/null
in_theme frost

until_ok 3000 mode_is rest
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 3000 filled_to 40
until_ok 3000 mode_is rest
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.62
until_ok 3000 filled_to 62
state=$(island)
echo "     osd: $(jq -c '[.osd.value, .osd.track, .osd.islandBox]' <<<"$state")"
check "volume 62: the OSD state reads 62 and is the track" state_has '.osd.value == "62" and .osd.kind == "track"'
check "the fill is 62 % of the track's width" state_has '(.osd.track.fill.w - .osd.track.box.w * 0.62) | fabs < 1'
check "from 40 to 62 the fill animation is 160 ms ease-out ending at 62 % of the track" state_has '.osd.fillAnimation == {ms: 160, curve: "ease-out", to: 0.62}'
check "the island box is 320 x 52" state_has '(.osd.islandBox.w - 320 | fabs) < 1 and (.osd.islandBox.h - 52 | fabs) < 1'
check "the value reads 62 in 13 px" state_has '.osd.value == "62" and .osd.valueFont[1] == 13'
filled=$(patch .osd.track.fill 0.5)
unfilled=$(jq -c '.osd.track | {x: (.fill.x + .fill.w), y: .box.y, w: (.box.w - .fill.w), h: .box.h}' <<<"$state")
state=$(jq --argjson u "$unfilled" '.osd.track.rest = $u' <<<"$state")
rest=$(patch .osd.track.rest 0.5)
# A 4 x 4 patch of the glass above the track, 14 px up, at the same x as the unfilled patch.
state=$(jq '.osd.track.glass = {x: (.osd.track.rest.x + .osd.track.rest.w / 2 - 2), y: (.osd.track.box.y - 14), w: 4, h: 4}' <<<"$state")
glass=$(patch .osd.track.glass 0.5)
echo "     filled $filled, unfilled $rest, glass $glass"
check "the filled part reads the accent #88C0D0 ($filled)" near "$filled" "136 192 208" 12
lum() { read -r r g b <<<"$1"; echo $((r + g + b)); }
check "the unfilled part reads lighter than the glass ($rest against $glass)" test "$(lum "$rest")" -gt "$(lum "$glass")"

until_ok 3000 mode_is rest
niri msg action spawn -- dots-call osd brightness 40%
until_ok 2000 eval 'island | jq -e ".mode == \"osd\" and .animating == false and .text == \"Brightness 40%\"" >/dev/null'
state=$(island)
echo "     osd: $(jq -c .osd <<<"$state")"
check "the brightness OSD keeps the bar" state_has '.osd.kind == "bar" and .osd.track == null and .osd.bars == "round"'

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 8000 mode_is rest
errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"
exit $((fails > 0))
}
