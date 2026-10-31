#!/usr/bin/env bash
# The Queue outlives the YouTube App's window: the island shows it and the play key drives it, a reopened App reads it, Space pauses and resumes it, and r repeats it from its last item back to its first.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-audio 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
sock=$XDG_RUNTIME_DIR/dots/youtube-audio.sock

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
line() { yt_state | jq -r '.look.nowPlaying[0]'; }
line_is() { yt_is --arg re "$1" '.look.nowPlaying[0] | test($re)'; }
repeat_is() { yt_is --arg r "$1" '.look.nowPlaying[1] == $r'; }
# mpv sends its events to every client, so the reply is picked out by its request id.
mpv_send() { timeout 2 socat -t 0.5 - "UNIX-CONNECT:$sock" 2>/dev/null <<<"$1" | jq -c 'select(.request_id == 7)'; }
mpv_get() { mpv_send "{\"command\":[\"get_property\",\"$1\"],\"request_id\":7}" | jq -c .data; }
mpv_is() { [ "$(mpv_get "$1")" = "$2" ]; }
audio_active() { systemctl --user is-active --quiet youtube-audio.service; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_shows() { island | jq -e --arg t "Aruarian Dance  $(date +%H:%M)" '.mode == "playing" and .text == $t' >/dev/null 2>&1; }
island_playing() { island | jq -e '.mode == "playing"' >/dev/null 2>&1; }
media() { niri msg action spawn -- dots-call media "$1"; }
open_app() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}

systemctl --user stop youtube-audio 2>/dev/null
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
open_app
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
wtype mjaja
until_ok 10000 line_is '^▶ Aruarian Dance — .* · \+2$'
check "m and two a make a Queue of three ($(line))" line_is '^▶ Aruarian Dance — Nujabes - Topic · .* · \+2$'

wtype -k Escape
until_ok 3000 yt_gone
check "Esc closes the App ($(yt_windows) windows)" yt_gone
app_gone() { [ -z "$(session_qs_pids shell/youtube.qml)" ]; }
until_ok 3000 app_gone
check "youtube-audio is still active after the window closed" audio_active
until_ok 5000 island_shows
check "and the island shows the song ($(island))" island_shows

media playPause
until_ok 3000 mpv_is pause true
until_ok 3000 eval '! island_playing'
check "the play key pauses the Queue ($(mpv_get pause))" mpv_is pause true
check "and the island leaves playing ($(island | jq -c .mode))" eval '! island_playing'
media playPause
until_ok 3000 mpv_is pause false
until_ok 3000 island_shows
check "the play key again resumes it ($(mpv_get pause))" mpv_is pause false
check "and the island shows the song again ($(island | jq -r .text))" island_shows

open_app
reads_queue() { line_is '^▶ Aruarian Dance — Nujabes - Topic · [0-9]+:[0-9]{2} / 4:27 · \+2$'; }
until_ok 3000 reads_queue
check "a reopened App reads the running Queue's title, time and +2 ($(line))" reads_queue
# A line that never left 0:00 would pass the shape above with no time-pos read at all.
time_runs() { reads_queue && ! line_is ' · 0:00 / '; }
until_ok 3000 time_runs
check "and its time runs ($(line))" time_runs

wtype ' '
until_ok 2000 line_is '^⏸ Aruarian Dance'
check "Space pauses the Queue: the line starts ⏸ ($(line))" line_is '^⏸ Aruarian Dance'
check "and mpv is paused ($(mpv_get pause))" mpv_is pause true
wtype ' '
until_ok 2000 line_is '^▶ Aruarian Dance'
check "Space again resumes it ($(line))" line_is '^▶ Aruarian Dance'
check "and mpv plays ($(mpv_get pause))" mpv_is pause false

check "repeat reads off at first ($(yt_state | jq -c '.look.nowPlaying[1]'))" repeat_is 'repeat off'
wtype r
until_ok 2000 repeat_is 'repeat on'
check "r turns repeat on ($(yt_state | jq -c '.look.nowPlaying[1]'), loop-playlist $(mpv_get loop-playlist))" repeat_is 'repeat on'
wtype r
until_ok 2000 repeat_is 'repeat off'
check "r again turns it off ($(yt_state | jq -c '.look.nowPlaying[1]'), loop-playlist $(mpv_get loop-playlist))" repeat_is 'repeat off'
wtype r
until_ok 2000 repeat_is 'repeat on'

mpv_send '{"command":["set_property","playlist-pos",2],"request_id":7}' >/dev/null
on_last() { line_is '^▶ Luv\(sic\) Part 3 — Nujabes - Topic · '; }
until_ok 5000 on_last
check "the Queue moved to its last item ($(line))" on_last
# A seek sent before the item has loaded is refused, so it waits for mpv to call the item seekable.
until_ok 5000 mpv_is seekable true
mpv_send '{"command":["seek",372,"absolute"],"request_id":7}' >/dev/null
wrapped() { yt_is '.queue.pos == 0' && reads_queue; }
until_ok 10000 wrapped
check "with repeat on, the last item ending plays the first again ($(line))" wrapped

wtype -k Escape
until_ok 3000 yt_gone
errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
