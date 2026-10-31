#!/usr/bin/env bash
# The YouTube App finds playlists and channels as well as videos: h and l move the type filter under the field and search the query again under it, and each type's rows draw as the boards draw them.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
calls=$DOTS_DEV_DIR/youtube.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
logged() { grep -qxF -- "$1" "$calls" 2>/dev/null; }
times_logged() { grep -cxF -- "$1" "$calls" 2>/dev/null; }
calls_text() { tail -n 4 "$calls" 2>/dev/null | cut -c1-60 | tr '\n' '|'; }
searches() { cat "$calls" 2>/dev/null | grep -c "^search ${1:-}"; }

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
check "the filter reads Videos Playlists Channels with Videos on ($(yt_state | jq -c '{type, chips: .look.chips, on: .look.chipsOn}'))" \
  yt_is '.type == "videos" and .look.chips == ["Videos", "Playlists", "Channels"] and .look.chipsOn == [true, false, false]'

wtype l
until_ok 1000 yt_is '.type == "playlists"'
playlists_on() { yt_is '.look.chipsOn == [false, true, false]' && [ "$(searches)" = 0 ]; }
check "l moves the filter to Playlists, with no search for an empty field ($(yt_state | jq -c '{type, on: .look.chipsOn}'))" playlists_on

wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '.rows | length == 3'
check "Enter searches playlists ($(calls_text))" logged "search nujabes playlists 0"
check "each playlist row draws its count where a video draws its duration ($(yt_state | jq -c '[.drawn[] | [.title, .duration]]'))" \
  yt_is '[.rows[].kind] == ["playlist", "playlist", "playlist"] and [.drawn[].duration] == ["14 videos", "300 videos", ""] and [.drawn[].title] == ["Modal Soul", "Lofi Archive", "Private Mix"]'
check "the list head counts the 3 rows ($(yt_state | jq -c .look.results))" yt_is '.look.results == ["RESULTS", "3"]'

wtype l
until_ok 3000 yt_is '.type == "channels" and ([.rows[].kind] | unique) == ["channel"]'
check "l on the results searches the query again as Channels ($(calls_text))" logged "search nujabes channels 0"
check "each channel row draws its name over its handle, with no duration ($(yt_state | jq -c '[.drawn[] | [.title, .channel, .duration]]'))" \
  yt_is '[.drawn[] | [.title, .channel, .duration]] == [["Nujabes", "@nujabes", ""], ["Nujabes - Topic", "", ""], ["Hydeout Productions", "@hydeout", ""]] and .look.chipsOn == [false, false, true]'
wtype l
sleep 0.3
stays_channels() { yt_is '.type == "channels"' && [ "$(searches)" = 2 ]; }
check "l on Channels stays there and searches nothing more ($(yt_state | jq -c .type))" stays_channels

wtype s
sleep 0.3
check "s on a channel row saves nothing ($(yt_state | jq -c '.look.sidebar[1]'))" yt_is '.look.sidebar | index("Saved 0") != null'

wtype -k Left
until_ok 1000 yt_is '.type == "playlists"'
wtype h
until_ok 3000 yt_is '.type == "videos" and (.rows | length) == 20'
back_to_videos() { [ "$(times_logged 'search nujabes playlists 0')" = 2 ] && logged "search nujabes videos 0"; }
check "Left then h come back to Videos, searching each type on the way ($(calls_text))" back_to_videos
check "Videos lists 20 video rows ($(yt_state | jq -c '[.rows[].kind] | unique'))" yt_is '([.rows[].kind] | unique) == ["video"] and .look.chipsOn == [true, false, false]'

wtype -k Escape
until_ok 3000 yt_gone
check "Esc closes the App" yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
