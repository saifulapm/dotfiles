#!/usr/bin/env bash
# The island's OSD: volume from the nested PipeWire's default sink, brightness from a fake brightnessctl.
fake=$(mktemp -d)
fake_log=$fake/argv
cat >"$fake/brightnessctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$fake_log"
echo "fake-bl,backlight,62,62%,100"
EOF
chmod +x "$fake/brightnessctl"
# bin/dots-dev hands this PATH to the shell, so the shell runs the fake and never the real backlight.
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
trap 'dev_stop; rm -f "$dev_out" "$dev_log"; rm -rf "$fake"' EXIT

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

niri msg action spawn -- qs ipc call osd brightness 5%+
until_ok 2000 mode_is osd
state=$(island)
echo "     island: $state"
check "the brightness key runs brightnessctl -m set 5%+" test "$(cat "$fake_log" 2>/dev/null)" = "-m set 5%+"
check "the island shows Brightness 62%" state_has '.text == "Brightness 62%"'
until_ok 3000 mode_is rest

rm -f "$fake_log"
timeout 2 qs ipc call osd brightness '5;rm' >/dev/null 2>&1
sleep 0.5
check "a step of 5;rm is refused and brightnessctl does not run" test ! -e "$fake_log"
check "a refused step shows no OSD" mode_is rest

niri msg action spawn -- wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
until_ok 2000 mode_is osd
osd_since=$(island | jq .since)
notify-send hi
until_ok 2000 mode_is notification
took=$(($(island | jq .since) - osd_since))
check "a notification takes the island from a showing OSD (${took} ms in)" test "$took" -lt 1500

until_ok 8000 mode_is rest
one_timer() { shell_status | jq -e '.timers == 1' >/dev/null; }
check "status reports timers 1 once the OSD has gone" one_timer

check "the live volume is still ${live_before#Volume: }" test "$(live_volume)" = "$live_before"
exit $((fails > 0))
