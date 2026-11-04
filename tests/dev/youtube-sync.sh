#!/usr/bin/env bash
# A store file that dots sync swapped in with mv --exchange, twice in a row, shows in the open YouTube App within 2 s, in a Playlist's rows and in the Saved count, and a save after it keeps what sync brought.
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
saved_count() { yt_is --arg s "Saved $1" '.look.sidebar[1] == $s'; }
store_ids() { jq -e --arg p "$1" --argjson ids "$2" '.playlists[$p].items | keys == $ids' "$store" >/dev/null 2>&1; }

legacy_theme paper >/dev/null
until_ok 3000 status_theme paper

item() { jq -c --arg id "$1" --argjson pos "$2" '.rows[] | select(.id == $id) | {id, title, channel, duration, thumb, pos: $pos, addedAt: 1, updatedAt: 1, deleted: false}' "$repo/dev/youtube/search.json"; }
mkdir -p "$(dirname "$store")"
jq -n --argjson a "$(item fakeVid0001 1)" --argjson b "$(item fakeVid0002 1)" '{version: 1, playlists: {
  saved: {id: "saved", name: "Saved", updatedAt: 0, items: {fakeVid0001: $a}},
  pl1: {id: "pl1", name: "Focus", createdAt: 1, updatedAt: 1, deleted: false, items: {fakeVid0002: $b}}}}' >"$store"

# One sync as dots-sync-merge does it: a temp file beside the store, swapped in with mv --exchange, the old inode unlinked.
sync_adds() {
  jq --argjson it "$(item fakeVid0003 2)" --arg p "$1" '.playlists[$p].items.fakeVid0003 = $it' "$store" >"$store.sync"
  mv --exchange "$store.sync" "$store"
  rm -f "$store.sync"
}

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up

until_ok 3000 saved_count 1
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j j j
until_ok 1000 yt_is '.view == "playlist" and .playlistId == "pl1"'
wtype -k Return
until_ok 1000 yt_is '.focus == "list"'
focus_ids() { yt_is --argjson t "$1" '[.drawn[].id] == $t'; }
until_ok 2000 focus_ids '["fakeVid0002"]'
check "Focus opens with its one video ($(yt_state | jq -c '[.drawn[].id]'))" focus_ids '["fakeVid0002"]'

sync_adds pl1
until_ok 2000 focus_ids '["fakeVid0002","fakeVid0003"]'
check "a first sync swap shows its new video in Focus ($(yt_state | jq -c '[.drawn[].id]'))" focus_ids '["fakeVid0002","fakeVid0003"]'

sync_adds saved
until_ok 2000 saved_count 2
check "a second sync swap makes the sidebar read Saved 2 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 2

# s on a Focus row saves it to Saved; the write must carry what sync brought.
wtype s
until_ok 2000 saved_count 3
check "s on a row afterwards makes Saved 3 ($(yt_state | jq -c '.look.sidebar[1]'))" saved_count 3
check "the file still holds Focus's two videos ($(jq -c '.playlists.pl1.items | keys' "$store" 2>/dev/null))" store_ids pl1 '["fakeVid0002","fakeVid0003"]'
check "and Saved's three ($(jq -c '.playlists.saved.items | keys' "$store" 2>/dev/null))" store_ids saved '["fakeVid0001","fakeVid0002","fakeVid0003"]'

# Another machine added a video at the position this one gave fakeVid0003, so the two tie; Shift+J must still move the cursor's video one row each time.
jq --argjson it "$(item fakeVid0004 2)" '.playlists.pl1.items.fakeVid0004 = $it' "$store" >"$store.sync"
mv --exchange "$store.sync" "$store"
rm -f "$store.sync"
until_ok 2000 focus_ids '["fakeVid0002","fakeVid0003","fakeVid0004"]'
wtype J
until_ok 2000 focus_ids '["fakeVid0003","fakeVid0002","fakeVid0004"]'
check "Shift+J moves fakeVid0002 past one of two videos at one position ($(yt_state | jq -c '[.drawn[].id]'))" focus_ids '["fakeVid0003","fakeVid0002","fakeVid0004"]'
wtype J
until_ok 2000 focus_ids '["fakeVid0003","fakeVid0004","fakeVid0002"]'
check "and again past the other ($(yt_state | jq -c '[.drawn[].id]'))" focus_ids '["fakeVid0003","fakeVid0004","fakeVid0002"]'

wtype -k Escape
until_ok 3000 yt_gone
errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
