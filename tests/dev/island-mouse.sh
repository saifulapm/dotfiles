#!/usr/bin/env bash
# The island by mouse: the wheel over it, a notification included, turns the volume one key step and shows the OSD; a click on the resting island opens its activity, the calendar when nothing is live, and a notification keeps its own click; the media card's controls run on click and on h, Space and l; a click during a download opens the YouTube App.
{
export DOTS_DEV_FAKE_CASTS=1
# bin/dots-dev-shell hands DOTS_YOUTUBE_APP to the shell, so a click runs this dots-youtube, which only says it ran.
fake=$(mktemp -d)
printf '#!/usr/bin/env bash\necho ran >>"%s/youtube"\n' "$fake" >"$fake/dots-youtube"
chmod +x "$fake/dots-youtube"
export DOTS_YOUTUBE_APP=$fake/dots-youtube
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
click_island() {
  local at
  at=$(island_spot "${1:-island}") || { echo "no island click area named ${1:-island} is drawn"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}
island_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-island" and .keyboard_interactivity == $k)' >/dev/null; }
opened() { until_ok 2000 mode_is "$1" && until_ok 2000 island_focus Exclusive; }
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
# An agent unlock turns the monitors off a second later, so the check wakes them as Saiful would.
unlock() {
  local n
  n=$(timeout 0.5 qs ipc call lock state | jq .monitorsOff)
  timeout 0.5 qs ipc call lock unlock "$@" >/dev/null
  until_ok 3000 lock_is ".locked == false and .monitorsOff > $n"
  niri msg action power-on-monitors
}
out=$DOTS_DEV_DIR/printed
: >"$out"
sender=
player=
cleanup() {
  rm -rf "$fake"
  pointer_stop
  [ -z "$sender" ] || kill "$sender" 2>/dev/null
  [ -z "$player" ] || kill "$player" 2>/dev/null
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
# A pointer over a notification holds it, so the pointer leaves for its 5 s to run out.
point move 20 600
until_ok 8000 mode_is rest

# With nothing live, a click opens the calendar with the keyboard, and Esc closes it.
click_island
opened calendar
check "a click on the resting island opens the calendar ($(island | jq -c '{mode, focused}'))" mode_is calendar
check "and gives it the keyboard" island_focus Exclusive
wtype -k Escape
until_ok 2000 mode_is rest
check "Esc closes it" mode_is rest

# A notification's click still opens the notification: its default action runs and the calendar never opens.
notify-send -a T -A default=Open "click me" >"$out" &
sender=$!
until_ok 2000 mode_is notification
click_island
until_ok 2000 bash -c "[ \"\$(cat '$out')\" = default ]"
check "a click on a notification runs its default action ($(cat "$out"))" test "$(cat "$out")" = default
check "and opens no calendar ($(island | jq -r .mode))" bash -c "! timeout 0.5 qs ipc call island state | jq -e '.mode == \"calendar\"' >/dev/null"
until_ok 8000 mode_is rest

# LIVE opens the sharing card.
fake_event '{"CastStartedOrChanged":{"cast":{"stream_id":3001,"session_id":3001,"kind":"PipeWire","target":{"Output":{"name":"winit"}},"is_dynamic_target":false,"is_active":true,"pid":null,"pw_node_id":null}}}' >/dev/null
until_ok 3000 mode_is sharing
click_island
opened sharingCard
check "a click on LIVE opens the sharing card ($(island | jq -c '{mode, text}'))" mode_is sharingCard
wtype -k Escape
until_ok 2000 mode_is sharing
fake_event '{"CastStopped":{"stream_id":3001}}' >/dev/null
until_ok 3000 mode_is rest

# A paused player is nothing live: a click opens the calendar, never the media card.
"$repo/bin/dev-fake-mpris" Track Artist &
player=$!
until_ok 3000 mode_is playing
busctl --user call org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Pause
until_ok 2000 mode_is rest
click_island
opened calendar
check "with the player paused a click opens the calendar ($(island | jq -r .mode))" mode_is calendar
wtype -k Escape
until_ok 2000 mode_is rest

# With media playing, a click opens the media card; its controls run on click and it stays through a pause.
busctl --user call org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Play
until_ok 2000 mode_is playing
click_island
opened mediaCard
reads() { [ "$(island | jq -r .text)" = "$1" ]; }
# What playerctl status reads, straight from the player's bus property.
status_is() { busctl --user get-property org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | grep -qx "s \"$1\""; }
title_is() { busctl --user get-property org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata 2>/dev/null | grep -q "\"xesam:title\" s \"$1\""; }
check "a click on the playing island opens the media card ($(island | jq -c '{mode, text}'))" reads "Track — Artist  h previous  ␣ pause  l next"
check "and gives it the keyboard" island_focus Exclusive
until_ok 2000 island_drawn media:playPause
click_island media:playPause
until_ok 2000 status_is Paused
check "a click on pause pauses the player" status_is Paused
until_ok 2000 reads "Track — Artist  h previous  ␣ play  l next"
check "the card stays, offering play ($(island | jq -c '{mode, text}'))" reads "Track — Artist  h previous  ␣ play  l next"
click_island media:next
until_ok 2000 reads "Next — Artist  h previous  ␣ play  l next"
check "a click on next moves to the next track" title_is Next
click_island media:previous
until_ok 2000 reads "Previous — Artist  h previous  ␣ play  l next"
check "a click on previous moves back" title_is Previous
wtype -k space
until_ok 2000 status_is Playing
check "Space plays it again" status_is Playing
wtype -k l
until_ok 2000 reads "Next — Artist  h previous  ␣ pause  l next"
check "l moves to the next track ($(island | jq -r .text))" reads "Next — Artist  h previous  ␣ pause  l next"
wtype -k h
until_ok 2000 reads "Previous — Artist  h previous  ␣ pause  l next"
check "h moves back ($(island | jq -r .text))" reads "Previous — Artist  h previous  ␣ pause  l next"
wtype -k Escape
until_ok 2000 mode_is playing
check "Esc closes the card back to the playing island" mode_is playing
check "and gives the keyboard back" island_focus None

kill "$player"
player=
until_ok 3000 mode_is rest

# A download's slot opens the YouTube App, as dots-youtube opens it or brings its window forward.
timeout 0.5 qs ipc call downloading start 1 1 "" "Low Tide" audio >/dev/null
until_ok 2000 mode_is downloading
click_island
until_ok 2000 test -s "$fake/youtube"
check "a click during a download runs dots-youtube ($(cat "$fake/youtube" 2>/dev/null | wc -l) runs)" test "$(cat "$fake/youtube" 2>/dev/null)" = ran
check "and opens no calendar ($(island | jq -r .mode))" mode_is downloading
timeout 0.5 qs ipc call downloading done >/dev/null
until_ok 3000 mode_is rest

# An agent's lease opens the lease card.
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
unlock claude 2
until_ok 3000 mode_is lease
click_island
opened leaseCard
check "a click on the lease slot opens the lease card ($(island | jq -c '{mode, focused}'))" mode_is leaseCard
wtype -k Escape
until_ok 2000 mode_is lease
check "Esc closes it, still unlocked" lock_is '.locked == false'

exit $((fails > 0))
}
