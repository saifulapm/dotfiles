#!/usr/bin/env bash
# With more Playlists than the sidebar holds, the list under PLAYLISTS scrolls so the chosen one, the question x asks under it and the name field n opens stay in view; p's picker scrolls its rows too, keeping the lit one and new playlist inside the window.
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
press() {
  local key=$1 n=$2
  for _ in $(seq "$n"); do wtype "$key"; done
}

# 45 sidebar rows outgrow the nested session's 1415 px window.
until_ok 3000 status_theme artboard

mkdir -p "$(dirname "$store")"
jq -n '{version: 1, playlists: ({saved: {id: "saved", name: "Saved", updatedAt: 0, items: {}}} + ([range(1; 46)] | map({key: "pl\(. + 100)", value: {id: "pl\(. + 100)", name: "List \(. + 100 | tostring | .[1:])", createdAt: ., updatedAt: ., deleted: false, items: {}}}) | from_entries))}' >"$store"

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
until_ok 2000 yt_is '(.playlists | length) == 45'

wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
press j 48
until_ok 2000 yt_is '.playlistId == "pl145"'
chosen_seen() { yt_is '.seen.chosen == true'; }
until_ok 1000 chosen_seen
check "j to the 45th Playlist scrolls the sidebar to keep it in view ($(yt_state | jq -c '[.playlistId, .seen]'))" chosen_seen
wtype x
until_ok 1000 yt_is '.confirming'
until_ok 1000 chosen_seen
check "x's question under it stays in view ($(yt_state | jq -c '[.confirm[0], .seen]'))" chosen_seen
wtype -k Escape
until_ok 1000 yt_is '.confirming == false'
wtype n
until_ok 1000 yt_is '.focus == "name"'
name_seen() { yt_is '.seen.name == true'; }
until_ok 1000 name_seen
check "n's name field below the last Playlist is in view ($(yt_state | jq -c .seen))" name_seen
wtype -k Escape
until_ok 1000 yt_is '.focus == "sidebar"'
press k 44
until_ok 2000 yt_is '.playlistId == "pl101"'
until_ok 1000 chosen_seen
check "k back to the first Playlist scrolls up to it ($(yt_state | jq -c '[.playlistId, .seen]'))" chosen_seen

press k 3
until_ok 1000 yt_is '.view == "search"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'
wtype p
until_ok 1000 yt_is '.picker.lit == 0'
check "the picker opens inside the window ($(yt_state | jq -c '.picker | {lit, litSeen, bottom}'))" yt_is '.picker.litSeen and .picker.bottom'
press j 44
until_ok 1000 yt_is '.picker.lit == 44'
lit_seen() { yt_is '.picker.litSeen and .picker.bottom'; }
until_ok 1000 lit_seen
check "j to the 45th Playlist in the picker keeps it in view, the picker inside the window ($(yt_state | jq -c '.picker | {lit, litSeen, bottom}'))" lit_seen
wtype j
until_ok 1000 yt_is '.picker.lit == 45'
check "and new playlist below it is there too" lit_seen
wtype -k Escape
until_ok 1000 yt_is '.picker == null'
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
