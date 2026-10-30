#!/usr/bin/env bash
# The island's OSD: volume from the nested PipeWire's default sink, brightness from a fake brightnessctl.
{
fake=$(mktemp -d)
fake_log=$fake/argv
cat >"$fake/brightnessctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$fake_log"
# An absolute step lands on its own value; a relative one on 62%.
case \$3 in *[+-]) pct=62 ;; *) pct=\${3%\%} ;; esac
echo "fake-bl,backlight,\$pct,\$pct%,100"
EOF
chmod +x "$fake/brightnessctl"
# bin/dots-dev hands this PATH to the shell, so the shell runs the fake and never the real backlight.
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { rm -rf "$fake"; }

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }
live_volume() { env -u PIPEWIRE_RUNTIME_DIR wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; }
live_before=$(live_volume)

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
state_has() { jq -e "$1" <<<"$state" >/dev/null; }

# The sink binds after the shell starts, so the island is watched for 2 s, not read once.
saw_osd=no
end=$(($(now_ms) + 2000))
while (($(now_ms) < end)); do
  mode_is osd && saw_osd=yes
  sleep 0.05
done
check "the shell starting shows no OSD" test "$saw_osd" = no
check "the island is at rest after start" mode_is rest

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 3000 mode_is osd
until_ok 3000 mode_is rest
niri msg action spawn -- wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
until_ok 2000 mode_is osd
state=$(island)
echo "     island: $state"
check "the nested volume reads 0.45" test "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "Volume: 0.45"
check "Volume Up shows Volume 45%" state_has '.mode == "osd" and .text == "Volume 45%"'
until_ok 3000 mode_is rest
# Both ends come from the shell's own mode clock, so the poll's latency does not count.
held=$(($(island | jq .since) - $(jq .since <<<"$state")))
check "the OSD lasts 1.5 ± 0.2 s (${held} ms)" test "$held" -ge 1300 -a "$held" -le 1700

# Volume Up as the bind runs it: raising a muted sink unmutes it, since wpctl set-volume alone keeps it muted and the OSD read 0.
wpctl set-mute @DEFAULT_AUDIO_SINK@ 1
raise=$(sed -n 's/^ *XF86AudioRaiseVolume .*spawn "sh" "-c" "\(.*\)"; }$/\1/p' "$repo/home/dot_config/niri/binds.kdl")
niri msg action spawn -- sh -c "$raise"
until_ok 2000 mode_is osd
check "Volume Up on a muted sink unmutes it ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" bash -c '! wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED'
until_ok 3000 mode_is rest

niri msg action spawn -- dots-call osd brightness 5%+
until_ok 2000 mode_is osd
state=$(island)
echo "     island: $state"
check "the brightness key runs brightnessctl -m set 5%+" test "$(cat "$fake_log" 2>/dev/null)" = "-m set 5%+"
check "the island shows Brightness 62%" state_has '.text == "Brightness 62%"'
until_ok 3000 mode_is rest

# The Shift brightness keys as binds.kdl spawns them, each an absolute step.
for pct in 100 1; do
  rm -f "$fake_log"
  niri msg action spawn -- dots-call osd brightness "$pct%"
  until_ok 2000 mode_is osd
  state=$(island)
  check "dots-call osd brightness $pct% runs brightnessctl -m set $pct%" test "$(cat "$fake_log" 2>/dev/null)" = "-m set $pct%"
  check "the island shows Brightness $pct% ($(jq -r .text <<<"$state"))" state_has ".text == \"Brightness $pct%\""
  until_ok 3000 mode_is rest
done

for step in '5;rm' 0% 101%; do
  rm -f "$fake_log"
  timeout 2 qs ipc call osd brightness "$step" >/dev/null 2>&1
  sleep 0.5
  check "a step of $step is refused and brightnessctl does not run" test ! -e "$fake_log"
  check "a refused $step shows no OSD" mode_is rest
done

niri msg action spawn -- wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
until_ok 2000 mode_is osd
osd_since=$(island | jq .since)
notify-send hi
until_ok 2000 mode_is notification
took=$(($(island | jq .since) - osd_since))
check "a notification takes the island from a showing OSD (${took} ms in)" test "$took" -lt 1500

until_ok 8000 mode_is rest

# Each theme's volume board: Blueprint's VOL, blocks and 062; Paper's bars and serif value; Artboard's glyph and rounded bar.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
osd_is() { island | jq -e --arg v "$1" '.mode == "osd" and .animating == false and .osd.value == $v' >/dev/null 2>&1; }
osd_reads() { until_ok 2000 osd_is "$1"; }
in_theme blueprint
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.62
osd_reads 062
state=$(island)
echo "     osd: $(jq -c .osd <<<"$state")"
check "blueprint: at volume 62 the OSD reads VOL, 12 lit blocks and 062" state_has '.osd.word == "VOL" and .osd.bars == "blocks" and .osd.lit == 12 and .osd.value == "062"'
value_cyan=$(grim -s 1 -t ppm -g "$(jq -r '.osd.valueBox | "\(.x | floor),\(.y | floor) \(.w | floor)x\(.h | floor)"' <<<"$state")" - | node -e '
  const b = require("fs").readFileSync(0), head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
  let n = 0;
  for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - 127) <= 10 && Math.abs(px[i * 3 + 1] - 227) <= 10 && Math.abs(px[i * 3 + 2] - 240) <= 10) n++;
  console.log(n);')
check "blueprint: the value draws in #7FE3F0 ($value_cyan px)" test "$value_cyan" -gt 15
in_theme paper
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.63
osd_reads 63
check "paper: the OSD reads VOL, 13 lit bars and 63 in Instrument Serif" eval 'island | jq -e ".osd.word == \"VOL\" and .osd.bars == \"bars\" and .osd.lit == 13 and .osd.valueFont[0] == \"Instrument Serif\"" >/dev/null'
in_theme artboard
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.64
osd_reads 64
check "artboard: the OSD draws its glyph and one rounded bar" eval 'island | jq -e ".osd.word == \"\" and .osd.bars == \"round\"" >/dev/null'
until_ok 3000 mode_is rest
one_timer() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "status reports timers 1 once the OSD has gone" one_timer

check "the live volume is still ${live_before#Volume: }" test "$(live_volume)" = "$live_before"
exit $((fails > 0))
}
