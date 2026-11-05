#!/usr/bin/env bash
# A Playlist plays whole: m replaces the Queue with its items in order, a appends them, S replaces it with them shuffled and the line ends shuffled, and Enter opens one video window that plays them straight through; an unavailable item reads Video unavailable, stays in the Playlist and reaches neither player, nothing goes to History, and deleting the Playlist leaves the Queue playing.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
store=$work/data/dots/youtube/ytcheck.json
mpv_log=$DOTS_DEV_DIR/youtube-mpv.log
sock=$XDG_RUNTIME_DIR/dots/youtube-audio.sock

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
# mpv sends its events to every client, so the reply is picked out by its request id.
mpv_get() {
  printf '{"command":["get_property","%s"],"request_id":7}\n' "$1" |
    timeout 2 socat -t 0.5 - "UNIX-CONNECT:$sock" 2>/dev/null | jq -c 'select(.request_id == 7) | .data'
}
queued() { mpv_get playlist | jq -r '[.[].filename | capture("v=(?<id>[A-Za-z0-9_-]{11})").id] | join(" ")'; }
queue_is() { [ "$(queued)" = "$1" ]; }
line_ends_shuffled() { yt_is '.look.nowPlaying[0] | endswith(" · shuffled")'; }
history_zero() { yt_is '.look.sidebar[2] == "History 0"'; }

systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
until_ok 3000 status_theme artboard

# Focus: four videos with a private one second.
item() { jq -c --arg id "$1" --argjson pos "$2" '.rows[] | select(.id == $id) | {id, title, channel, duration, thumb, pos: $pos, addedAt: 1, updatedAt: 1, deleted: false}' "$repo/dev/youtube/search.json"; }
gone='{"id": "fakeGone001", "title": "", "channel": "", "duration": null, "thumb": "", "unavailable": "made private", "pos": 2, "addedAt": 1, "updatedAt": 1, "deleted": false}'
mkdir -p "$(dirname "$store")"
jq -n --argjson a "$(item fakeVid0001 1)" --argjson g "$gone" --argjson b "$(item fakeVid0002 3)" --argjson c "$(item fakeVid0003 4)" --argjson d "$(item fakeVid0005 5)" '{version: 1, playlists: {
  saved: {id: "saved", name: "Saved", updatedAt: 0, items: {}},
  pl1: {id: "pl1", name: "Focus", createdAt: 1, updatedAt: 1, deleted: false, items: {fakeVid0001: $a, fakeGone001: $g, fakeVid0002: $b, fakeVid0003: $c, fakeVid0005: $d}}}}' >"$store"

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE_SEED=7 DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up

wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j j j
until_ok 1000 yt_is '.playlistId == "pl1" and (.drawn | length) == 5'
check "Focus lists the private item second, dimmed, as Video unavailable · made private ($(yt_state | jq -c '.drawn[1] | {title, duration, dimmed}'))" \
  yt_is '.drawn[1].title == "Video unavailable · made private" and .drawn[1].duration == "—" and .drawn[1].dimmed and (.drawn[0].dimmed | not)'

# m from the sidebar entry, as letters act there too.
wtype m
until_ok 10000 queue_is "fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005"
check "m on Focus replaces the Queue with its items in order, the private one left out ($(queued))" queue_is "fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005"
playing_first() { yt_is '.look.nowPlaying[0] | test("^▶ Aruarian Dance — Nujabes - Topic · ")'; }
until_ok 5000 playing_first
check "and the line plays its first, not shuffled ($(yt_state | jq -c '.look.nowPlaying[0]'))" yt_is '.look.nowPlaying[0] | test("^▶ Aruarian Dance — Nujabes - Topic · .* · \\+3$")'

wtype -k Return
until_ok 1000 yt_is '.focus == "list"'
wtype a
until_ok 5000 queue_is "fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005 fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005"
check "a appends them in order ($(queued))" queue_is "fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005 fakeVid0001 fakeVid0002 fakeVid0003 fakeVid0005"

wtype S
until_ok 5000 queue_is "fakeVid0003 fakeVid0002 fakeVid0005 fakeVid0001"
check "S replaces the Queue with the same four in another order ($(queued))" queue_is "fakeVid0003 fakeVid0002 fakeVid0005 fakeVid0001"
until_ok 5000 line_ends_shuffled
check "and the line ends shuffled ($(yt_state | jq -c '.look.nowPlaying[0]'))" line_ends_shuffled
check "History is unchanged after playing and shuffling Focus ($(yt_state | jq -c '.look.sidebar[2]'))" history_zero

wtype -k Return
one_window() { [ "$(mpv_windows)" = 1 ]; }
until_ok 10000 one_window
video_line() { grep -- '--force-window=immediate' "$mpv_log" | tail -1; }
plays_through() { video_line | grep -qE 'v=fakeVid0001 .*v=fakeVid0002 .*v=fakeVid0003 .*v=fakeVid0005$' && ! video_line | grep -q fakeGone001; }
check "Enter opens one video window playing its four straight through, the private one left out ($(video_line | grep -oE 'v=[A-Za-z0-9_-]+' | tr '\n' ' '))" plays_through
check "and the Queue paused for it ($(yt_state | jq -c '.queue.paused'))" yt_is '.queue.paused == true'
check "History is still unchanged ($(yt_state | jq -c '.look.sidebar[2]'))" history_zero
check "and the private item stays in Focus ($(yt_state | jq -c '.look.sidebar[4]'))" yt_is '.look.sidebar[4] == "Focus 5"'
systemctl --user stop 'youtube-video-*' 2>/dev/null

# Deleting the Playlist the Queue plays from leaves the Queue as it is.
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype x
until_ok 1000 yt_is '.confirming'
wtype y
until_ok 2000 yt_is '(.playlists | length) == 0'
sleep 0.5
check "deleting Focus leaves the Queue its four, still shuffled ($(queued))" queue_is "fakeVid0003 fakeVid0002 fakeVid0005 fakeVid0001"
check "and its line still reads ($(yt_state | jq -c '.look.nowPlaying[0]'))" line_ends_shuffled

wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
