#!/usr/bin/env bash
# Hi-Fi's volume OSD is a glass VU meter whose needle pins at +45 above 100; its brightness OSD keeps the bar.
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
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
osd_is() { island | jq -e --arg v "$1" '.mode == "osd" and .animating == false and .osd.value == $v' >/dev/null 2>&1; }
# Sets the nested sink's volume and waits for the settled OSD to read it.
volume() {
  until_ok 3000 mode_is rest
  wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1"
  until_ok 2000 osd_is "$2"
  state=$(island)
  echo "     osd: $(jq -c .osd <<<"$state")"
}
# Pixels within $5 of r g b in a 7 x 7 box centred on the state's point $1, or in the box at jq path $1 when it has w and h.
near() {
  local geo
  geo=$(jq -r "$1 | if .w then \"\(.x | floor),\(.y | floor) \(.w | floor)x\(.h | floor)\" else \"\(.x - 3 | floor),\(.y - 3 | floor) 7x7\" end" <<<"$state")
  grim -s 1 -t ppm -g "$geo" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}

until_ok 5000 shell_status >/dev/null
in_theme hi-fi

volume 0.62 62
check "at volume 62 the OSD is a meter reading 62 with the needle at 10.8 degrees" state_has '.osd.kind == "meter" and .osd.value == "62" and .osd.needleAngle == 10.8 and .osd.word == "VOLUME"'
check "the meter is 320 px wide ($(jq -c .osd.meter.box <<<"$state"))" state_has '.osd.meter.box.w == 320'
# A 20 px square at the dial's top left holds no scale, label or needle, only the glass #141617.
state=$(jq '.osd.meter.glass = {x: (.osd.meter.box.x + 8), y: (.osd.meter.box.y + 8), w: 20, h: 20}' <<<"$state")
glass=$(near .osd.meter.glass 20 22 23 3)
check "the panel is glass #141617 ($glass of 400 px)" test "$glass" -gt 380
red=$(near .osd.meter.red 251 73 52 12)
check "the red zone reads #FB4934 ($red px)" test "$red" -gt 6
# The 1.5 px needle covers no pixel whole, so its pixels are #FABD2F blended into the glass: bright, with amber's green to red ratio of 0.76 and little blue.
amber=$(grim -s 1 -t ppm -g "$(jq -r '.osd.meter.needle | "\(.x - 3 | floor),\(.y - 3 | floor) 7x7"' <<<"$state")" - | node -e '
  const b = require("fs").readFileSync(0), head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
  let n = 0;
  for (let i = 0; i < head[1] * head[2]; i++) if (px[i * 3] >= 150 && Math.abs(px[i * 3 + 1] / px[i * 3] - 0.756) <= 0.05 && px[i * 3 + 2] / px[i * 3] <= 0.3) n++;
  console.log(n);')
check "the needle near its tip reads amber #FABD2F over the glass ($amber px)" test "$amber" -ge 5
# Ink at 6 % over the glass blends to about #212220 in the row under the top border.
lit=$(near .osd.highlightBox 33 34 32 4)
check "the row under the top border is the highlight ($lit px)" test "$lit" -gt 280

volume 0.95 95
check "at volume 95 the value reads 95 and the needle is in the red zone, past the 90 mark's 36 degrees" state_has '.osd.value == "95" and .osd.needleAngle >= 36'

volume 1.20 120
check "the nested sink took 1.20 ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" test "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "Volume: 1.20"
check "at volume 120 the needle pins at 45 degrees and the value reads 120" state_has '.osd.needleAngle == 45 and .osd.value == "120"'

until_ok 3000 mode_is rest
niri msg action spawn -- dots-call osd brightness 40%
until_ok 2000 eval 'island | jq -e ".mode == \"osd\" and .animating == false and .text == \"Brightness 40%\"" >/dev/null'
state=$(island)
echo "     osd: $(jq -c .osd <<<"$state")"
check "the brightness OSD keeps the bar" state_has '.osd.kind == "bar" and .osd.meter == null and .osd.bars == "blocks" and .osd.lit == 8'

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 8000 mode_is rest
exit $((fails > 0))
}
