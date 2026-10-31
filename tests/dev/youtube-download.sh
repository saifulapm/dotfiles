#!/usr/bin/env bash
# d and D download a row's audio or video through dots-youtube-get, one at a time in youtube-get-dev, into the scratch music and video folders; the island shows each, the row then draws the download mark in each theme, a second d starts nothing, a failed row offers Enter to retry, D on a Playlist takes every item not yet downloaded and counts them in the island, and closing the App leaves the queue running.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-get-dev youtube-audio 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
store=$work/data/dots/youtube/ytcheck.json
music=$work/music/YouTube
videos=$work/videos/YouTube
get_log=$DOTS_DEV_DIR/youtube-get.log
# The nested session's own state dir, where the App's theme is too.
index=$XDG_STATE_HOME/dots/youtube/downloads.json
sock=$XDG_RUNTIME_DIR/dots/youtube-audio.sock

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_says() { island | jq -e --arg re "$1" '.text | test($re)' >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
has() { compgen -G "$1" >/dev/null; }
gets() { grep -c . "$get_log" 2>/dev/null || echo 0; }
marked() { yt_is --argjson i "$1" '.drawn[$i].mark == true'; }
get_units() { systemctl --user list-units --all --plain --no-legend 'youtube-get*' | grep -c ' active ' || true; }
# mpv sends its events to every client, so the reply is picked out by its request id.
mpv_get() {
  printf '{"command":["get_property","%s"],"request_id":7}\n' "$1" |
    timeout 2 socat -t 0.5 - "UNIX-CONNECT:$sock" 2>/dev/null | jq -c 'select(.request_id == 7) | .data'
}
loaded() { mpv_get playlist | jq -r '[.[].filename] | join("\n")'; }
launch() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}

systemctl --user stop youtube-get-dev youtube-audio 'youtube-video-*' 2>/dev/null
rm -f "$get_log" "$index" "$DOTS_DEV_DIR/youtube-get-fail" "$DOTS_DEV_DIR/youtube-get.json"
"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper

# Focus: four videos with a private one second.
item() { jq -c --arg id "$1" --argjson pos "$2" '.rows[] | select(.id == $id) | {id, title, channel, duration, thumb, pos: $pos, addedAt: 1, updatedAt: 1, deleted: false}' "$repo/dev/youtube/search.json"; }
gone='{"id": "fakeGone001", "title": "", "channel": "", "duration": null, "thumb": "", "unavailable": "made private", "pos": 2, "addedAt": 1, "updatedAt": 1, "deleted": false}'
mkdir -p "$(dirname "$store")"
jq -n --argjson a "$(item fakeVid0001 1)" --argjson g "$gone" --argjson b "$(item fakeVid0002 3)" --argjson c "$(item fakeVid0003 4)" --argjson d "$(item fakeVid0005 5)" '{version: 1, playlists: {
  saved: {id: "saved", name: "Saved", updatedAt: 0, items: {}},
  pl1: {id: "pl1", name: "Focus", createdAt: 1, updatedAt: 1, deleted: false, items: {fakeVid0001: $a, fakeGone001: $g, fakeVid0002: $b, fakeVid0003: $c, fakeVid0005: $d}}}}' >"$store"

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv DOTS_YOUTUBE_YTDLP=$repo/dev/youtube/yt-dlp $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work XDG_MUSIC_DIR=$work/music XDG_VIDEOS_DIR=$work/videos $repo/bin/dots-youtube"
launch
check "the App's open made the download index" test -f "$index"
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
check "no row is marked before any download" yt_is '[.drawn[].mark] | any | not'

wtype d
until_ok 5000 island_says '^↓ Aruarian Dance · [0-9]+%$'
check "d: the island reads ↓ Aruarian Dance · n% ($(island | jq -c .text))" island_says '^↓ Aruarian Dance · [0-9]+%$'
until_ok 15000 marked 0
check "then the row draws the download mark ($(yt_state | jq -c '.drawn[0] | {id, mark}'))" marked 0
check "and its audio is in the music folder" has "$music/*fakeVid0001*.opus"
check "fetched as bestaudio with the cover and tags embedded" grep -q -- '-f bestaudio -x --embed-thumbnail --embed-metadata' "$get_log"
check "the island leaves the download once the queue is done" until_ok 3000 bash -c '! timeout 0.5 qs ipc call island state | jq -e ".mode == \"downloading\"" >/dev/null'

for theme in artboard blueprint paper; do
  "$repo/bin/dots" theme "$theme" >/dev/null
  until_ok 3000 status_theme "$theme"
  check "$theme: the downloaded row draws its mark, and only it ($(yt_state | jq -c '[.drawn[0:3][].mark]'))" yt_is '.drawn[0].mark and (.drawn[1].mark | not)'
  # The cursor's row is lit: Paper's ink and Blueprint's accent fill it, so its mark takes the surface colour; Artboard's light tint keeps the blue.
  case $theme in paper) ink='#faf6ec' ;; blueprint) ink='#0a1526' ;; artboard) ink='#2638c9' ;; esac
  check "$theme: the lit row's mark draws in $ink ($(yt_state | jq -c '[.cursor, .drawn[0].markInk]'))" yt_is --arg ink "$ink" '.cursor == 0 and .drawn[0].markInk == $ink'
done

before=$(gets)
wtype d
sleep 2
check "d on a row already downloaded starts nothing ($(($(gets) - before)) yt-dlp runs)" test "$(gets)" = "$before"

wtype j D
until_ok 15000 marked 1
check "D on the second row downloads its video at most 1080p" has "$videos/*fakeVid0002*.webm"
check "with the 1080p format" grep -q -- 'bv\*\[height<=1080\]+ba/b\[height<=1080\]' "$get_log"

# fakeVid0003 fails until the file goes.
echo fakeVid0003 >"$DOTS_DEV_DIR/youtube-get-fail"
wtype j d
until_ok 10000 island_says '^↓ failed · '
check "a failure reads ↓ failed · <title> · HTTP 403 in the island ($(island | jq -c .text))" island_says '^↓ failed · .* · HTTP 403$'
failed_row() { yt_is '.drawn[2].channel == "download failed · HTTP 403 · ↵ retry"'; }
until_ok 3000 failed_row
check "and the row says so with Enter to retry ($(yt_state | jq -c '.drawn[2] | {channel, channelColor}'))" failed_row
# The lit row draws its channel line in the row's light ink, so the colour is read from the row below.
wtype j
until_ok 1000 yt_is '.cursor == 3'
check "off the cursor it reads in Paper's danger colour ($(yt_state | jq -c '.drawn[2].channelColor'))" yt_is '.drawn[2].channelColor == "#c8381e"'
wtype k
until_ok 1000 yt_is '.cursor == 2'
rm -f "$DOTS_DEV_DIR/youtube-get-fail"
wtype -k Return
until_ok 15000 marked 2
check "Enter retries it, and the retry completes ($(yt_state | jq -c '.drawn[2] | {mark, channel}'))" yt_is '.drawn[2].mark and .drawn[2].channel == "Nujabes - Topic"'
check "and Enter played nothing ($(mpv_windows) mpv windows)" test "$(mpv_windows)" = 0

# Focus: fakeVid0002's video is there and fakeGone001 is private, so D queues the other three.
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j j j
until_ok 1000 yt_is '.playlistId == "pl1" and (.drawn | length) == 5'
check "Focus marks the items downloaded so far ($(yt_state | jq -c '[.drawn[].mark]'))" yt_is '[.drawn[].mark] == [true, false, true, true, false]'
echo 1 >"$DOTS_DEV_DIR/youtube-get-pace"
wtype D
until_ok 8000 island_says '^↓ Focus 1 / 3 · '
check "D on Focus counts the three items not yet in video ($(island | jq -c .text))" island_says '^↓ Focus 1 / 3 · Aruarian Dance · [0-9]+%$'
check "one youtube-get unit runs ($(get_units))" test "$(get_units)" = 1

# The App closes mid-queue: the queue goes on and the marks catch up when it opens again.
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
wtype -k Escape
until_ok 3000 yt_gone
until_ok 8000 island_says '^↓ Focus 2 / 3 · '
check "with the App closed the island keeps counting ($(island | jq -c .text))" island_says '^↓ Focus 2 / 3 · '
until_ok 40000 has "$videos/*fakeVid0005*.webm"
check "and the last item lands" has "$videos/*fakeVid0005*.webm"
rm -f "$DOTS_DEV_DIR/youtube-get-pace"
no_units() { [ "$(get_units)" = 0 ]; }
check "no youtube-get unit is left once the queue is done" until_ok 5000 no_units
launch
wtype -k Tab
wtype j j j
until_ok 2000 yt_is '.playlistId == "pl1" and (.drawn | length) == 5'
check "the reopened App marks every item but the private one ($(yt_state | jq -c '[.drawn[].mark]'))" yt_is '[.drawn[].mark] == [true, false, true, true, true]'

# m on Focus loads each item's file: a song's audio first, else its video.
wtype m
from_files() { [ "$(loaded | grep -c "^$work/")" = 4 ]; }
until_ok 10000 from_files
check "m on Focus loads all four items from their files, none streamed ($(loaded | sed "s|$work/||" | tr '\n' ' '))" from_files
first_audio() { loaded | grep -qx "$music/.*fakeVid0001.*\.opus"; }
check "fakeVid0001 from its audio" first_audio
plays_file() { mpv_get path | grep -q "^\"$work/"; }
check "and the Queue plays that file ($(mpv_get path))" until_ok 5000 plays_file

# Its files deleted, fakeVid0001 streams again, leaves the index and loses its mark.
rm -f "$music"/*fakeVid0001* "$videos"/*fakeVid0001*
wtype m
streams_first() { loaded | head -1 | grep -qx 'https://www.youtube.com/watch?v=fakeVid0001'; }
until_ok 10000 streams_first
check "with its files gone, m streams fakeVid0001 ($(loaded | head -1))" streams_first
unlisted() { ! jq -e '.files.fakeVid0001' "$index" >/dev/null; }
check "the index no longer lists it" until_ok 3000 unlisted
unmarked() { yt_is '.drawn[0].mark == false and .drawn[2].mark == true'; }
check "and its row loses the mark ($(yt_state | jq -c '[.drawn[].mark]'))" until_ok 3000 unmarked

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"
exit $((fails > 0))
}
