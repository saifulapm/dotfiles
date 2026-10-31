#!/usr/bin/env bash
# Enter, m and a on a YouTube video put it on top of History in XDG_STATE_HOME/dots/youtube/history.json, a replay moves it up leaving one entry, the History view lists them newest first under its sidebar count, and a history.json that does not parse is never written over.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
mpv_log=$DOTS_DEV_DIR/youtube-mpv.log
# The nested session's XDG_STATE_HOME is scratch, so History starts empty and the live one is never touched.
history=$XDG_STATE_HOME/dots/youtube/history.json

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
mpv_count() { [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length')" = "$1" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
history_ids() { jq -c '[.[].id]' "$history" 2>/dev/null; }
history_is() { [ "$(history_ids)" = "$1" ]; }
history_count() { yt_is --arg s "History $1" '.look.sidebar[2] == $s'; }
rows_are() { yt_is --argjson ids "$1" '[.rows[].id] == $ids'; }

systemctl --user stop youtube-audio 'youtube-video-*' 2>/dev/null
rm -f "$history"
"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
open_app() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}
close_app() {
  wtype -k Escape
  until_ok 3000 yt_gone
}
search() {
  wtype /
  until_ok 1000 yt_is '.focus == "field"'
  wtype nujabes
  until_ok 1000 yt_is '.query == "nujabes"'
  wtype -k Return
  until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
}
to_history() {
  wtype -k Tab
  until_ok 1000 yt_is '.focus == "sidebar"'
  wtype jj
  until_ok 1000 yt_is '.view == "history"'
  wtype -k Tab
  until_ok 1000 yt_is '.focus == "list"'
}
# A video's window takes the keys, so it is closed before the App is typed into again.
close_videos() {
  systemctl --user stop 'youtube-video-*'
  until_ok 3000 mpv_count 0
}

open_app
check "a first open's History count reads 0 ($(yt_state | jq -c '.look.sidebar[2]'))" history_count 0
to_history
check "an empty History reads ↵ or m plays a video ($(yt_state | jq -c .empty))" yt_is '.empty == ["↵ or m plays a video"] and .rows == []'
search

wtype j
until_ok 1000 yt_is '.cursor == 1'
wtype -k Return
until_ok 5000 mpv_count 1
close_videos
until_ok 2000 history_is '["fakeVid0002"]'
check "Enter on row 1 puts it in history.json ($(history_ids))" history_is '["fakeVid0002"]'
check "with its title, channel, duration and thumb ($(jq -c '.[0]' "$history" 2>/dev/null))" \
  jq -e '.[0] | {id, title, channel, duration, thumb} == {"id": "fakeVid0002", "title": "Feather (feat. Cise Starr & Akin)", "channel": "Nujabes - Topic", "duration": 296, "thumb": "fakeVid0002"} and (.at | type) == "number"' "$history"
wtype km
until_ok 3000 history_is '["fakeVid0001","fakeVid0002"]'
check "m on row 0 puts it on top ($(history_ids))" history_is '["fakeVid0001","fakeVid0002"]'
wtype jja
until_ok 3000 history_is '["fakeVid0003","fakeVid0001","fakeVid0002"]'
check "a on row 2 puts it on top ($(history_ids))" history_is '["fakeVid0003","fakeVid0001","fakeVid0002"]'
wtype km
until_ok 3000 history_is '["fakeVid0002","fakeVid0003","fakeVid0001"]'
check "m on row 1 again moves it to the top, leaving one entry ($(history_ids))" history_is '["fakeVid0002","fakeVid0003","fakeVid0001"]'
until_ok 1000 history_count 3
check "the History count follows: 3 ($(yt_state | jq -c '.look.sidebar[2]'))" history_count 3

to_history
check "the History view lists them newest first ($(yt_state | jq -c '[.rows[].id]'))" rows_are '["fakeVid0002","fakeVid0003","fakeVid0001"]'
thumbs_shown() { yt_is '(.drawn | length) == 3 and all(.drawn[]; .thumb.shown)'; }
until_ok 3000 thumbs_shown
check "each with its thumbnail ($(yt_state | jq -c '[.drawn[].thumb.file]'))" thumbs_shown
wtype jm
until_ok 3000 history_is '["fakeVid0003","fakeVid0002","fakeVid0001"]'
check "m on a History row plays it and moves it up ($(history_ids))" history_is '["fakeVid0003","fakeVid0002","fakeVid0001"]'
until_ok 1000 rows_are '["fakeVid0003","fakeVid0002","fakeVid0001"]'
check "and the view follows ($(yt_state | jq -c '[.rows[].id]'))" rows_are '["fakeVid0003","fakeVid0002","fakeVid0001"]'
wtype j
until_ok 1000 yt_is '.cursor == 2'
wtype -k Return
until_ok 5000 mpv_count 1
check "Enter on a History row plays it ($(tail -1 "$mpv_log"))" grep -qF 'watch?v=fakeVid0001' <(tail -1 "$mpv_log")
close_videos
until_ok 3000 history_is '["fakeVid0001","fakeVid0003","fakeVid0002"]'
check "and moves it to the top ($(history_ids))" history_is '["fakeVid0001","fakeVid0003","fakeVid0002"]'
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
close_app
check "Esc from History, then from Search, closes the App" yt_gone

# A history.json that does not parse: nothing reads from it and nothing writes over it.
mkdir -p "$(dirname "$history")"
printf '[{"id": ' >"$history"
before=$(sha256sum <"$history")
open_app
check "with a broken history.json the History count reads 0 ($(yt_state | jq -c '.look.sidebar[2]'))" history_count 0
search
wtype m
until_ok 10000 yt_is '.queue.idle == false'
sleep 1
check "m plays but adds nothing: the file is unchanged ($(head -c 40 "$history"))" test "$(sha256sum <"$history")" = "$before"
check "and the App says why in its log" grep -qF 'history.json does not parse' "$log"
close_app

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
