#!/usr/bin/env bash
# p on a video opens a picker of the Playlists over the dimmed list: Enter adds the video to the one under its cursor, a Playlist already holding it is marked and keeps one copy, n names a new one for it, and Esc adds nothing; inside a Playlist, Shift+J and Shift+K move an item, x removes it, and the order holds after the App opens again.
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
sidebar_has() { yt_is --arg s "$1" '.look.sidebar | index($s) != null'; }
titles_are() { yt_is --argjson t "$1" '[.drawn[].title] == $t'; }

until_ok 3000 status_theme artboard

# Focus already holds Feather; Gym is empty.
feather=$(jq -c '.rows[] | select(.id == "fakeVid0002") | {id, title, channel, duration, thumb, pos: 1, addedAt: 1, updatedAt: 1, deleted: false}' "$repo/dev/youtube/search.json")
mkdir -p "$(dirname "$store")"
jq -n --argjson f "$feather" '{version: 1, playlists: {
  saved: {id: "saved", name: "Saved", updatedAt: 0, items: {}},
  pl1: {id: "pl1", name: "Focus", createdAt: 1, updatedAt: 1, deleted: false, items: {fakeVid0002: $f}},
  pl2: {id: "pl2", name: "Gym", createdAt: 2, updatedAt: 2, deleted: false, items: {}}}}' >"$store"

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
open_app() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 yt_up
}
open_focus() {
  wtype -k Tab
  until_ok 1000 yt_is '.focus == "sidebar"'
  wtype j j j
  until_ok 1000 yt_is '.playlistId == "pl1"'
  wtype -k Return
  until_ok 1000 yt_is '.focus == "list"'
}

open_app
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20 and .focus == "list"'

wtype j
until_ok 1000 yt_is '.cursor == 1'
wtype p
until_ok 1000 yt_is '.picker != null'
check "p on Feather opens the picker over the dimmed list, Focus marked already in ($(yt_state | jq -c '.picker | {title, rows, fresh}'))" \
  yt_is '.picker.title == ["p", "Add \"Feather (feat. Cise Starr & Akin)\" to"] and .picker.rows == ["Focus 1 already in", "Gym 0"] and .picker.fresh == "n new playlist" and .dimmed'
check "its cursor starts on Gym, the first that lacks it, and its legend is its own ($(yt_state | jq -c '.picker | {lit, keys, below}'))" \
  yt_is '.picker.lit == 1 and .picker.keys == ["j/k move", "↵ add", "n new", "esc cancel"] and .picker.below'
wtype k
until_ok 1000 yt_is '.picker.lit == 0'
wtype -k Return
until_ok 1000 yt_is '.picker == null'
sleep 0.3
check "Enter on Focus, which holds it, leaves one copy ($(yt_state | jq -c '.playlists[0].count'))" \
  yt_is '.playlists[0].count == 1 and (.dimmed | not)'

wtype k
until_ok 1000 yt_is '.cursor == 0'
wtype p
until_ok 1000 yt_is '.picker.lit == 0'
wtype -k Return
until_ok 2000 sidebar_has "Focus 2"
check "p on Aruarian Dance then Enter on Focus adds it: Focus 2 ($(yt_state | jq -c '.look.sidebar'))" sidebar_has "Focus 2"
wtype j j
until_ok 1000 yt_is '.cursor == 2'
wtype p
until_ok 1000 yt_is '.picker.lit == 0'
wtype -k Return
until_ok 2000 sidebar_has "Focus 3"
wtype j
wtype p
until_ok 1000 yt_is '.picker != null'
wtype -k Escape
until_ok 1000 yt_is '.picker == null'
check "Esc closes the picker adding nothing ($(yt_state | jq -c '.look.sidebar'))" yt_is '.picker == null and (.look.sidebar | index("Focus 3")) != null and (.look.sidebar | index("Gym 0")) != null'

# n from the picker names a new Playlist that takes the video, and the results keep the focus.
wtype p
until_ok 1000 yt_is '.picker != null'
wtype n
until_ok 1000 yt_is '.focus == "name" and .picker == null'
wtype Picked
wtype -k Return
until_ok 2000 sidebar_has "Picked 1"
check "n in the picker, Picked, Enter makes Picked holding the video, the results still focused ($(yt_state | jq -c '[.look.sidebar, .view, .focus]'))" \
  yt_is '(.look.sidebar | index("Picked 1")) != null and .view == "search" and .focus == "list" and .cursor == 3'

open_focus
until_ok 2000 titles_are '["Feather (feat. Cise Starr & Akin)", "Aruarian Dance", "Luv(sic) Part 3"]'
check "Focus lists its three in the order they were added ($(yt_state | jq -c '[.drawn[].title]'))" \
  titles_are '["Feather (feat. Cise Starr & Akin)", "Aruarian Dance", "Luv(sic) Part 3"]'
wtype J
until_ok 1000 titles_are '["Aruarian Dance", "Feather (feat. Cise Starr & Akin)", "Luv(sic) Part 3"]'
check "Shift+J on item 1 makes it item 2, the cursor with it ($(yt_state | jq -c '[[.drawn[].title], .cursor]'))" \
  yt_is '[.drawn[].title] == ["Aruarian Dance", "Feather (feat. Cise Starr & Akin)", "Luv(sic) Part 3"] and .cursor == 1'
wtype k
until_ok 1000 yt_is '.cursor == 0'
wtype K
sleep 0.3
check "Shift+K on item 1 moves nothing" yt_is '[.drawn[].title] == ["Aruarian Dance", "Feather (feat. Cise Starr & Akin)", "Luv(sic) Part 3"] and .cursor == 0'
wtype j j
until_ok 1000 yt_is '.cursor == 2'
wtype J
sleep 0.3
check "Shift+J on the last item moves nothing" yt_is '[.drawn[].title] == ["Aruarian Dance", "Feather (feat. Cise Starr & Akin)", "Luv(sic) Part 3"] and .cursor == 2'
wtype x
until_ok 1000 yt_is '(.drawn | length) == 2'
check "x on an item removes it and the count drops by 1 ($(yt_state | jq -c '[.look.results, .cursor]'))" \
  yt_is '.look.results[1] | startswith("2 videos")'
check "and the cursor stays on the last row" yt_is '.cursor == 1'
removed() { jq -e '.playlists.pl1.items.fakeVid0003.deleted == true' "$store" >/dev/null 2>&1; }
until_ok 2000 removed
check "the store keeps the removed item as a tombstone" removed
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
wtype -k Escape
until_ok 3000 yt_gone

open_app
open_focus
until_ok 2000 titles_are '["Aruarian Dance", "Feather (feat. Cise Starr & Akin)"]'
check "opened again, Focus keeps the moved order ($(yt_state | jq -c '[.drawn[].title]'))" titles_are '["Aruarian Dance", "Feather (feat. Cise Starr & Akin)"]'
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
