#!/usr/bin/env bash
# Enter on a video while the Queue plays pauses the Queue first; the island and the play key follow the video, and once its window closes the Queue stays paused until the play key resumes it, though another paused MPRIS player registered before both.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
  kill "$other" 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
sock=$XDG_RUNTIME_DIR/dots/youtube-audio.sock
video="Feather (feat. Cise Starr & Akin)"

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
mpv_count() { [ "$(mpv_windows)" = "$1" ]; }
units_are() { yt_is --argjson n "$1" '.units | length == $n'; }
line() { yt_state | jq -r '.look.nowPlaying[0]'; }
line_is() { yt_is --arg re "$1" '.look.nowPlaying[0] | test($re)'; }
# mpv sends its events to every client, so the reply is picked out by its request id.
mpv_send() { timeout 2 socat -t 0.5 - "UNIX-CONNECT:$sock" 2>/dev/null <<<"$1" | jq -c 'select(.request_id == 7)'; }
mpv_get() { mpv_send "{\"command\":[\"get_property\",\"$1\"],\"request_id\":7}" | jq -c .data; }
mpv_is() { [ "$(mpv_get "$1")" = "$2" ]; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_shows() { island | jq -e --arg t "$1  $(date +%H:%M)" '.mode == "playing" and .text == $t' >/dev/null 2>&1; }
island_playing() { island | jq -e '.mode == "playing"' >/dev/null 2>&1; }
media() { niri msg action spawn -- dots-call media "$1"; }
# The video's mpv has no socket, so its pause is read as the PlaybackStatus of the MPRIS player titled as its row.
mpris() { busctl --user get-property "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player "$2" -j 2>/dev/null; }
status_of() {
  local name
  for name in $(busctl --user list --acquired --no-legend | awk '$1 ~ /^org\.mpris\.MediaPlayer2\./ {print $1}'); do
    mpris "$name" Metadata | jq -e --arg t "$1" '.data["xesam:title"].data == $t' >/dev/null 2>&1 && mpris "$name" PlaybackStatus | jq -r .data
  done
}
status_is() { [ "$(status_of "$1")" = "$2" ]; }
other_is() { [ "$(mpris org.mpris.MediaPlayer2.dotsfake PlaybackStatus | jq -r .data)" = "$1" ]; }

systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
# Registered first, so a key that falls back to the bus's first player reaches it and not the Queue.
"$repo/bin/dev-fake-mpris" Other Artist &
other=$!
until_ok 3000 other_is Playing
busctl --user call org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Pause
until_ok 2000 other_is Paused
check "another MPRIS player is on the bus first, paused" other_is Paused

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
wtype m
until_ok 10000 line_is '^▶ Aruarian Dance'
until_ok 3000 mpv_is pause false
check "m plays the Queue ($(line))" mpv_is pause false

wtype j
until_ok 1000 yt_is '.cursor == 1'
# The video's window takes the keys once it opens, so from here the App gets none until it closes.
wtype -k Return
until_ok 5000 units_are 1
until_ok 5000 mpv_count 1
until_ok 3000 line_is '^⏸ Aruarian Dance'
check "Enter on a video pauses the Queue: the line reads ⏸ ($(line))" line_is '^⏸ Aruarian Dance'
check "and the Queue's mpv is paused ($(mpv_get pause))" mpv_is pause true
until_ok 5000 island_shows "$video"
check "the island shows the video's title ($(island | jq -r .text))" island_shows "$video"

media playPause
until_ok 3000 status_is "$video" Paused
until_ok 3000 eval '! island_playing'
check "the play key pauses the video ($(status_of "$video"))" status_is "$video" Paused
check "and not the Queue, which stays paused ($(mpv_get pause))" mpv_is pause true
check "and the island leaves playing ($(island | jq -c .mode))" eval '! island_playing'

systemctl --user stop 'youtube-video-*'
until_ok 3000 mpv_count 0
check "stopping the video's unit closes its window ($(mpv_windows))" mpv_count 0
sleep 0.5
check "the Queue stays paused ($(mpv_get pause))" mpv_is pause true
check "and its line reads ⏸ ($(line))" line_is '^⏸ Aruarian Dance'

media playPause
until_ok 3000 mpv_is pause false
until_ok 3000 island_shows "Aruarian Dance"
check "the play key then resumes the Queue ($(mpv_get pause))" mpv_is pause false
check "the island shows the Queue's song ($(island | jq -r .text))" island_shows "Aruarian Dance"
check "and the other player stays paused ($(mpris org.mpris.MediaPlayer2.dotsfake PlaybackStatus | jq -r .data))" other_is Paused

wtype -k Return -k Return
until_ok 5000 units_are 3
until_ok 5000 mpv_count 2
until_ok 3000 mpv_is pause true
check "two videos open while the Queue plays ($(mpv_windows) windows) and pause it ($(mpv_get pause))" mpv_is pause true
systemctl --user stop 'youtube-video-*'
until_ok 3000 mpv_count 0
sleep 0.5
check "closing both leaves the Queue paused ($(mpv_get pause))" mpv_is pause true
media playPause
until_ok 3000 mpv_is pause false
until_ok 3000 island_shows "Aruarian Dance"
check "the play key resumes the Queue after both close ($(mpv_get pause))" mpv_is pause false
check "the island shows its song ($(island | jq -r .text))" island_shows "Aruarian Dance"
check "and the other player stays paused ($(mpris org.mpris.MediaPlayer2.dotsfake PlaybackStatus | jq -r .data))" other_is Paused

# mpv keeps pause from one file to the next, so m after a video must clear the pause the video left.
wtype -k Return
until_ok 5000 mpv_count 1
until_ok 3000 mpv_is pause true
systemctl --user stop 'youtube-video-*'
until_ok 3000 mpv_count 0
until_ok 3000 yt_is '.focus == "list"'
wtype m
until_ok 5000 line_is '^▶ Feather'
check "m after a video closed plays its row, not paused ($(line), pause $(mpv_get pause))" mpv_is pause false

wtype -k Escape
errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
