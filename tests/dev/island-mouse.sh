#!/usr/bin/env bash
# The island by mouse: the wheel over it, a notification included, turns the volume one key step and shows the OSD.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
volume_is() { [ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "Volume: $1" ]; }
# The island's click area in output pixels, as `island box` answers it.
island_spot() {
  local box
  box=$(timeout 0.5 qs ipc call island box "$1" 2>/dev/null)
  [ -n "$box" ] && [ "$box" != null ] || return 1
  jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"' <<<"$box"
}
island_drawn() { island_spot "$1" >/dev/null; }
# The pointer over the island, then the wheel turned $1 notches, down when positive.
island_wheel() {
  local at
  at=$(island_spot island) || { echo "no island click area is drawn"; return 1; }
  # shellcheck disable=SC2086
  point move $at
  point wheel "$1"
}

until_ok 5000 shell_status >/dev/null
until_ok 2000 mode_is rest
until_ok 2000 island_drawn island
check "the resting island draws its click area" island_drawn island

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 3000 mode_is osd
until_ok 3000 mode_is rest
island_wheel -1
until_ok 2000 mode_is osd
check "one notch up over the resting island raises the volume one key step ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.45
check "and shows the volume OSD ($(island | jq -c '{mode, text}'))" bash -c "timeout 0.5 qs ipc call island state | jq -e '.mode == \"osd\" and .text == \"Volume 45%\"' >/dev/null"
until_ok 3000 mode_is rest
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50
until_ok 3000 mode_is osd
until_ok 3000 mode_is rest
island_wheel 1
until_ok 2000 volume_is 0.45
check "one notch down lowers it one step ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.45
until_ok 3000 mode_is rest

wpctl set-volume @DEFAULT_AUDIO_SINK@ 0
until_ok 3000 mode_is osd
until_ok 3000 mode_is rest
island_wheel 1
# A step at 0 % changes nothing, so no OSD comes; the poll only gives the wheel its second.
until_ok 1000 mode_is osd
check "one notch down at 0 % leaves it at 0 % ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.00
until_ok 3000 mode_is rest

# A notification takes the wheel for the volume too, and stays on the island.
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 3000 mode_is osd
until_ok 3000 mode_is rest
notify-send -a T "wheel me"
until_ok 2000 mode_is notification
island_wheel -1
until_ok 2000 volume_is 0.45
check "one notch up over a notification raises the volume ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is 0.45
check "and the notification stays on the island" mode_is notification

exit $((fails > 0))
}
