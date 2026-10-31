#!/usr/bin/env bash
# Enter on a YouTube row plays it through bin/dots-youtube-play in an mpv window of its own unit, youtube-video-<n>, at most 1080p; two Enters on one row are two windows, each stopped by its unit's name.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
mpv_log=$DOTS_DEV_DIR/youtube-mpv.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
mpv_count() { [ "$(mpv_windows)" = "$1" ]; }
units_are() { yt_is --argjson n "$1" '.units | length == $n'; }
units() { yt_state | jq -r '.units[]'; }
all_active() { local u; [ -n "$(units)" ] || return 1; for u in $(units); do systemctl --user is-active --quiet "$u.service" || return 1; done; }
none_active() { local u; [ -n "$(units)" ] || return 1; for u in $(units); do ! systemctl --user is-active --quiet "$u.service" || return 1; done; }

# A video window left from an earlier run would take youtube-video-1 and count as a window here.
systemctl --user stop 'youtube-video-*' 2>/dev/null
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
wtype j
until_ok 1000 yt_is '.cursor == 1'
check "the cursor is on row 1, fakeVid0002 ($(yt_state | jq -c '{cursor, id: .rows[.cursor].id}'))" yt_is '.rows[.cursor].id == "fakeVid0002"'

wtype -k Return
until_ok 5000 units_are 1
until_ok 5000 mpv_count 1
check "Enter started one youtube-video-<n> unit ($(yt_state | jq -c .units))" yt_is '.units | length == 1 and all(test("^youtube-video-[0-9]+$"))'
check "its unit is active" all_active
check "its mpv window, app id mpv, opened ($(mpv_windows))" mpv_count 1
check "mpv was handed the row's watch URL ($(tail -1 "$mpv_log" 2>/dev/null))" grep -qF 'https://www.youtube.com/watch?v=fakeVid0002' "$mpv_log"
check "and the at most 1080p format" grep -qF -- '--ytdl-format=bv*[height<=1080]+ba/b[height<=1080]' "$mpv_log"
first=$(units)
systemctl --user stop "$first.service"
until_ok 3000 mpv_count 0
check "stopping $first closes its window ($(mpv_windows))" mpv_count 0

wtype -k Return -k Return
until_ok 5000 units_are 3
until_ok 5000 mpv_count 2
check "two Enters in quick succession started two more units ($(yt_state | jq -c .units))" \
  yt_is '(.units | length) == 3 and (.units[1:] | unique | length) == 2'
check "both are active" all_active
check "and two mpv windows are open ($(mpv_windows))" mpv_count 2
check "each was handed fakeVid0002 ($(grep -c 'watch?v=fakeVid0002' "$mpv_log"))" test "$(grep -c 'watch?v=fakeVid0002' "$mpv_log")" = 3
# shellcheck disable=SC2046
systemctl --user stop $(yt_state | jq -r '.units[1:][] + ".service"')
until_ok 3000 mpv_count 0
check "systemctl --user stop on their names closes both windows ($(mpv_windows))" mpv_count 0
check "and leaves none of the App's units active" none_active

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
