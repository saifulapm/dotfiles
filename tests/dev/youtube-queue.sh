#!/usr/bin/env bash
# m on a YouTube row plays it audio-only in the Queue, the unit youtube-audio, and a appends to it; the now-playing line shows the title, time and +N, and a fast run of a loses no item.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-audio 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
mpv_log=$DOTS_DEV_DIR/youtube-mpv.log
sock=$XDG_RUNTIME_DIR/dots/youtube-audio.sock

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
line() { yt_state | jq -r '.look.nowPlaying[0]'; }
line_is() { yt_is --arg re "$1" '.look.nowPlaying[0] | test($re)'; }
# mpv sends its events to every client, so the reply is picked out by its request id.
mpv_get() {
  printf '{"command":["get_property","%s"],"request_id":7}\n' "$1" |
    timeout 2 socat -t 0.5 - "UNIX-CONNECT:$sock" 2>/dev/null | jq -c 'select(.request_id == 7) | .data'
}
count_is() { [ "$(mpv_get playlist-count)" = "$1" ]; }
audio_active() { systemctl --user is-active --quiet youtube-audio.service; }
queue_starts() { grep -c -- '--idle=yes' "$mpv_log" 2>/dev/null || echo 0; }

# A Queue left from an earlier run would answer this check's first m.
systemctl --user stop youtube-audio 2>/dev/null
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
check "with no Queue the line is empty ($(yt_state | jq -c '.look.nowPlaying'))" yt_is '.look.nowPlaying[0] == ""'

wtype m
playing_first() { line_is '^▶ Aruarian Dance — Nujabes - Topic · 0:0[0-9] / 4:27$'; }
until_ok 10000 playing_first
check "m on the first row reads ▶ Aruarian Dance — Nujabes - Topic · 0:00 / 4:27 ($(line))" playing_first
check "youtube-audio is active" audio_active
check "and no video window opened ($(mpv_windows))" test "$(mpv_windows)" = 0
check "state() reports the Queue beside the line ($(yt_state | jq -c '.queue | {pos, count, paused, title, channel, secs}'))" \
  yt_is '.queue.pos == 0 and .queue.count == 1 and .queue.paused == false and .queue.title == "Aruarian Dance" and .queue.channel == "Nujabes - Topic" and .queue.secs == 267'

wtype jaja
ends_two() { line_is ' · \+2$'; }
until_ok 5000 ends_two
check "a on two more rows ends the line +2 ($(line))" ends_two
check "and the Queue holds 3 ($(mpv_get playlist-count))" count_is 3

wtype m
until_ok 5000 count_is 1
check "m while three play replaces them: playlist-count 1 ($(mpv_get playlist-count))" count_is 1
check "and the line reads the row m was on ($(line))" line_is '^▶ Luv\(sic\) Part 3 — Nujabes - Topic · '

systemctl --user stop youtube-audio
until_ok 3000 line_is '^$'
check "stopping youtube-audio empties the line ($(line))" line_is '^$'
wtype a
until_ok 10000 count_is 1
check "a with no Queue running starts it with that one item ($(mpv_get playlist-count))" count_is 1
check "youtube-audio is active again" audio_active
check "and the line reads it ($(line))" line_is '^▶ Luv\(sic\) Part 3 — Nujabes - Topic · 0:0[0-9] / 6:15$'

systemctl --user stop youtube-audio
until_ok 3000 line_is '^$'
wtype kkkkk
until_ok 1000 yt_is '.cursor == 0'
before=$(queue_starts)
wtype "$(printf 'aj%.0s' {1..20})"
until_ok 10000 count_is 20
want=$(seq -f 'https://www.youtube.com/watch?v=fakeVid%04g' 1 20 | jq -R . | jq -sc .)
got=$(mpv_get playlist | jq -c '[.[].filename]')
check "a pressed 20 times fast with no Queue running leaves 20 items ($(mpv_get playlist-count))" count_is 20
check "in the order pressed" test "$got" = "$want"
check "started by one unit ($(($(queue_starts) - before)) Queue starts)" test "$(($(queue_starts) - before))" = 1

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
