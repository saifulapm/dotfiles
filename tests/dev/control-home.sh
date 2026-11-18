#!/usr/bin/env bash
# Control's Home by keys and mouse: hjkl and the arrows move between tiles, - and = step Sound and Brightness, Enter flips Do Not Disturb, opens the calendar and locks; a click acts as Enter and the wheel steps a slider.
{
fake=$(mktemp -d)
fake_log=$fake/argv
cat >"$fake/brightnessctl" <<EOF2
#!/usr/bin/env bash
echo "\$*" >>"$fake_log"
echo "fake-bl,backlight,62,62%,100"
EOF2
chmod +x "$fake/brightnessctl"
# bin/dots-dev hands this PATH to the shell, so the shell runs the fake and never the real backlight.
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"
cleanup() {
  pointer_stop
  rm -rf "$fake"
}

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
control() { timeout 0.5 qs ipc call control state 2>/dev/null; }
control_is() { control | jq -e "$@" >/dev/null 2>&1; }
at_rest() { island_is '.surface == null and .animating == false'; }
surfaces_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
open_control() {
  niri msg action spawn -- dots-call control toggle
  until_ok 3000 island_is '.surface == "control" and .animating == false'
  until_ok 2000 surfaces_focus Exclusive
  until_ok 2000 control_is '.keyboard and .settled'
}
cursor_is() { control_is --arg c "$1" '.cursor == $c'; }
press() {
  wtype "$@"
  sleep 0.12
}
volume_is() { [ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "Volume: $1" ]; }
dnd() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e ".dnd == $1" >/dev/null; }
tile_on() { control_is --arg t "$1" ".tiles[] | select(.title == \$t) | .on == $2"; }

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0

open_control
press l
until_ok 1000 cursor_is bluetooth
check "from Wi-Fi, l focuses Bluetooth" cursor_is bluetooth
press h
press j
until_ok 1000 cursor_is brightness
check "and j from Wi-Fi focuses Brightness, the tile below" cursor_is brightness
press -k Up
until_ok 1000 cursor_is bluetooth
press -k Left
until_ok 1000 cursor_is wifi
press -k Right
until_ok 1000 cursor_is bluetooth
check "the arrows do the same: Up, Left and Right move along Wi-Fi's row" cursor_is bluetooth
press -k Down
until_ok 1000 cursor_is brightness
check "and Down lands on Brightness" cursor_is brightness

press k
press l
press l
until_ok 1000 cursor_is sound
press =
until_ok 2000 volume_is 0.35
check "= on Sound at 30% sets 35% ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.35
# wtype reads a bare - as an option, so minus goes by its keysym.
press -k minus
press -k minus
until_ok 2000 volume_is 0.25
check "and - twice sets 25% ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.25

press j
until_ok 1000 cursor_is brightness
until_ok 2000 control_is '.tiles[] | select(.title == "Brightness") | .detail == "62%"'
press =
stepped() { grep -qx -- '-m -d fake-bl set 5%+' "$fake_log" 2>/dev/null; }
until_ok 2000 stepped
check "= on Brightness raises the built-in panel one step (brightnessctl $(tail -1 "$fake_log"))" stepped

press j
press j
press h
until_ok 1000 cursor_is dnd
press -k Return
until_ok 2000 dnd true
check "Enter on Do Not Disturb turns it on" dnd true
check "and its tile inverts" tile_on "Do Not Disturb" true
press -k Return
until_ok 2000 dnd false

# A click is Enter, and the wheel steps a slider.
click_box control-tile:dnd
until_ok 2000 dnd true
check "a click on Do Not Disturb turns it on, as Enter does" dnd true
click_box control-tile:dnd
until_ok 2000 dnd false
wheel_box control-tile:sound -1
until_ok 2000 volume_is 0.30
check "a wheel notch up over Sound raises it 5% ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.30
check "and Control stays on Home" control_is '.open and .page == "home"'

for _ in 1 2 3 4 5; do press k; done
until_ok 1000 cursor_is calendar
check "k from the bottom row climbs to Calendar ($(control | jq -c .cursor))" cursor_is calendar
press -k Return
until_ok 3000 island_is '.mode == "calendar"'
check "Enter on Calendar shows the calendar card ($(island | jq -c '{mode, surface}'))" island_is '.mode == "calendar" and .surface == null'
press -k Escape
until_ok 3000 at_rest

open_control
for _ in 1 2 3; do press j; done
press l
until_ok 1000 cursor_is lock
press -k Return
locked() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e '.locked' >/dev/null; }
until_ok 3000 locked
check "Enter on Lock locks the session" locked
check "and Control closed" control_is '.open == false'
exit "$fails"
}
