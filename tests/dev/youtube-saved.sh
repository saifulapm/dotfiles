#!/usr/bin/env bash
# s saves the YouTube row under the cursor to Saved, once, in XDG_DATA_HOME/dots/youtube/<machine>.json, and Saved lists it with its thumbnail after the App opens again; a store file that does not parse is never written over.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -rf "$work"
}
log=$work/youtube.log
store=$work/data/dots/youtube/ytcheck.json

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
store_holds() { jq -e '(.playlists.saved.items | keys) == ["fakeVid0002"] and (.playlists.saved.items.fakeVid0002 | {id, title, channel, duration, thumb}) == {"id": "fakeVid0002", "title": "Feather (feat. Cise Starr & Akin)", "channel": "Nujabes - Topic", "duration": 296, "thumb": "fakeVid0002"}' "$store" >/dev/null 2>&1; }
saved_count() { yt_is --arg s "Saved $1" '.look.sidebar[1] == $s'; }

until_ok 3000 status_theme artboard
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
open_app() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}
search() {
  wtype /
  until_ok 1000 yt_is '.focus == "field"'
  wtype nujabes
  until_ok 1000 yt_is '.query == "nujabes"'
  wtype -k Return
  until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
}
to_saved() {
  wtype -k Tab
  until_ok 1000 yt_is '.focus == "sidebar"'
  wtype j
  until_ok 1000 yt_is '.view == "saved"'
}
close_app() {
  wtype -k Escape
  until_ok 3000 yt_gone
}

open_app
check "a first open's Saved count reads 0 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 0
to_saved
check "its Saved reads Nothing saved yet over s saves a video ($(yt_state | jq -c .empty))" yt_is '.empty == ["Nothing saved yet", "s saves a video"] and .rows == []'
wtype k
until_ok 1000 yt_is '.view == "search"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'

search
wtype j
until_ok 1000 yt_is '.cursor == 1'
wtype s
until_ok 2000 saved_count 1
check "s on row 1 makes the Saved count 1 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 1
wtype s
until_ok 1000 test -s "$store"
check "s on it again leaves it 1 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 1
check "the store holds the video with its five fields ($(jq -c '.playlists.saved.items' "$store" 2>/dev/null))" \
  store_holds
close_app
check "Esc closes the App" yt_gone

open_app
check "opened again, the Saved count reads 1 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 1
to_saved
saved_shown() { yt_is '(.drawn | length) == 1 and .drawn[0].thumb.shown'; }
until_ok 3000 saved_shown
check "Saved lists the video with its title, channel, duration and thumbnail ($(yt_state | jq -c '.drawn[0] | {id, title, channel, duration, thumb: .thumb.file}'))" \
  yt_is '.drawn[0] | .id == "fakeVid0002" and .title == "Feather (feat. Cise Starr & Akin)" and .channel == "Nujabes - Topic" and .duration == "4:56" and .thumb.shown and .thumb.file == "fakeVid0002.jpg"'
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
close_app

# A store that does not parse: nothing reads from it and nothing writes over it.
mkdir -p "$(dirname "$store")"
printf '{"playlists": {"saved": ' >"$store"
before=$(sha256sum <"$store")
open_app
check "with a broken store the Saved count reads 0 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 0
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'
search
wtype s
sleep 1
check "s saves nothing ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 0
check "and the file is unchanged" test "$(sha256sum <"$store")" = "$before"
close_app

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
