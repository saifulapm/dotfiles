#!/usr/bin/env bash
# YouTube by mouse: a wheel notch over the results scrolls them and j still moves the cursor into view; a click on a result plays it as Enter does; a pointer resting on a row while j is pressed never moves the cursor.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  pointer_stop
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
mpv_log=$DOTS_DEV_DIR/youtube-mpv.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_box() { timeout 0.5 qs ipc -p "$yt_qml" call youtube box "$1" 2>/dev/null; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
mpv_count() { [ "$(mpv_windows)" = "$1" ]; }
units_are() { yt_is --argjson n "$1" '.units | length == $n'; }
# The output point in the middle of a named click area in YouTube's window.
yt_spot() { app_spot youtube "$(yt_box "$1")" || { echo "no click area named $1 is drawn" >&2; return 1; }; }

# A video window left from an earlier run would count as a window here.
systemctl --user stop 'youtube-video-*' 2>/dev/null
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
float_app youtube
# Floating, the window keeps the output's height, which shows all 20 rows; 500 px leaves some below the fold.
niri msg action set-window-height --id "$(app_window_id youtube)" 500
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
check "a search lists 20 results past the window's bottom ($(yt_state | jq -c '.listed'))" yt_is '.listed.top == 0 and .listed.bottom >= 0 and .listed.bottom < 19'

at=$(yt_spot yt-row:4)
# shellcheck disable=SC2086
point move $at
wtype j
until_ok 1000 yt_is '.cursor == 1'
sleep 0.3
check "j under a pointer resting on the fifth row moves the cursor to row 1, not the hovered row ($(yt_state | jq -c '{cursor}'))" yt_is '.cursor == 1'
wtype k
until_ok 1000 yt_is '.cursor == 0'

at=$(yt_spot yt-row:2)
# shellcheck disable=SC2086
point move $at
point wheel 1
until_ok 1000 yt_is '.listed.top != 0'
check "one wheel notch down over the list moves its first shown row to row 1 ($(yt_state | jq -c '{cursor, listed}'))" yt_is '.listed.top == 1 and .cursor == 0'
wtype j
until_ok 1000 yt_is '.cursor == 1'
check "j then moves the cursor one row, with its row in view ($(yt_state | jq -c '{cursor, listed}'))" \
  yt_is '.cursor == 1 and .listed.top <= .cursor and .cursor <= .listed.bottom'

at=$(yt_spot yt-row:2)
# shellcheck disable=SC2086
point click $at
until_ok 5000 units_are 1
until_ok 5000 mpv_count 1
check "a click on the third result started one youtube-video-<n> unit ($(yt_state | jq -c '{cursor, units}'))" yt_is '.units | length == 1 and all(test("^youtube-video-[0-9]+$"))'
check "its mpv window opened ($(mpv_windows))" mpv_count 1
check "mpv was handed the third result's watch URL ($(tail -1 "$mpv_log" 2>/dev/null))" grep -qF 'https://www.youtube.com/watch?v=fakeVid0003' "$mpv_log"
check "and the cursor is on the clicked row ($(yt_state | jq -c '{cursor}'))" yt_is '.cursor == 2'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
