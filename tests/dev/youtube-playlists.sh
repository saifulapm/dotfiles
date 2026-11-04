#!/usr/bin/env bash
# The sidebar lists each Playlist under PLAYLISTS with its count, oldest first, and j and k reach it; its view heads its name, count and length over its rows numbered in its own order, or names p while it is empty; a name typed with a newline, a bidi override and 300 characters draws as one line.
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

legacy_theme paper >/dev/null
until_ok 3000 status_theme paper

# Focus holds three videos whose positions put the last added first; Gym is empty; the third's name is what a careless paste could type.
long=$'Low\nTide\u202e '"$(printf 'x%.0s' $(seq 300))"
item() { jq -c --arg id "$1" --argjson pos "$2" '.rows[] | select(.id == $id) | {id, title, channel, duration, thumb, pos: $pos, addedAt: 1, updatedAt: 1, deleted: false}' "$repo/dev/youtube/search.json"; }
mkdir -p "$(dirname "$store")"
jq -n --arg long "$long" --argjson a "$(item fakeVid0001 2)" --argjson b "$(item fakeVid0002 3)" --argjson c "$(item fakeVid0003 1)" '{version: 1, playlists: {
  saved: {id: "saved", name: "Saved", updatedAt: 0, items: {}},
  pl2: {id: "pl2", name: "Gym", createdAt: 2, updatedAt: 2, deleted: false, items: {}},
  pl1: {id: "pl1", name: "Focus", createdAt: 1, updatedAt: 1, deleted: false, items: {fakeVid0001: $a, fakeVid0002: $b, fakeVid0003: $c}},
  pl3: {id: "pl3", name: $long, createdAt: 3, updatedAt: 3, deleted: false, items: {}},
  pl0: {id: "pl0", name: "Gone", createdAt: 0, updatedAt: 4, deleted: true, items: {}}}}' >"$store"

exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_MACHINE=ytcheck DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up

sidebar_is() { yt_is --argjson s "$1" '.look.sidebar[0:6] == $s'; }
until_ok 3000 sidebar_is '["Search", "Saved 0", "History 0", "PLAYLISTS", "Focus 3", "Gym 0"]'
check "the sidebar lists Focus 3 and Gym 0 under PLAYLISTS, oldest first, and no deleted one ($(yt_state | jq -c '.look.sidebar'))" \
  sidebar_is '["Search", "Saved 0", "History 0", "PLAYLISTS", "Focus 3", "Gym 0"]'
check "the long name lists as one line with no newline or override" \
  yt_is '(.look.sidebar | length) == 7 and (.look.sidebar[6] | test("\n|‮") | not) and (.look.sidebar[6] | startswith("Low Tide"))'

wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j j j
until_ok 1000 yt_is '.view == "playlist" and .playlistId == "pl1"'
focus_drawn() { yt_is '[.drawn[] | [.number, .title]] == [["1", "Luv(sic) Part 3"], ["2", "Aruarian Dance"], ["3", "Feather (feat. Cise Starr & Akin)"]]'; }
until_ok 2000 focus_drawn
check "j from History opens Focus, its name in the title strip ($(yt_state | jq -c '[.view, .playlistId, .look.title[1]]'))" \
  yt_is '.view == "playlist" and .playlistId == "pl1" and .look.title[1] == "Focus"'
check "its head reads Focus · 3 videos · 16 min ($(yt_state | jq -c .look.results))" yt_is '.look.results == ["Focus", "3 videos · 16 min"]'
check "its rows are numbered in its own order ($(yt_state | jq -c '[.drawn[] | [.number, .title]]'))" focus_drawn

wtype j
until_ok 1000 yt_is '.playlistId == "pl2"'
check "Gym, empty, reads p adds a video here ($(yt_state | jq -c '[.empty, .look.results]'))" \
  yt_is '.empty == ["p adds a video here"] and .rows == [] and .look.results == ["Gym", "0 videos · 0 min"]'
wtype j j
until_ok 1000 yt_is '.playlistId == "pl3"'
check "j stops on the last Playlist" yt_is '.playlistId == "pl3" and .view == "playlist"'
check "and the title strip draws its name as one line" yt_is '(.look.title[1] | test("\n|‮") | not)'
wtype k k
until_ok 1000 yt_is '.playlistId == "pl1"'
wtype -k Return
until_ok 1000 yt_is '.focus == "list"'
check "Enter on Focus in the sidebar moves to its list" yt_is '.focus == "list" and .view == "playlist" and .cursor == 0'
check "where the legend names the whole-playlist keys ($(yt_state | jq -c '.look.legend[0:3]'))" \
  yt_is '.look.legend[0:3] == ["↵ PLAY AS VIDEO", "M PLAY IN QUEUE", "S SHUFFLE"]'
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
check "Esc in a Playlist goes back to Search" yt_is '.view == "search"'

# n names a new Playlist, here a second Focus; e renames it; x asks under its row, Esc keeps it and y deletes it.
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
check "with the sidebar focused the legend names n, e, x, open and list ($(yt_state | jq -c .look.legend))" \
  yt_is '.look.legend == ["N NEW", "E RENAME", "X DELETE", "↵ OPEN", "TAB LIST"]'
wtype n
until_ok 1000 yt_is '.focus == "name" and .naming == "new" and .nameField == ""'
wtype Focus
until_ok 1000 yt_is '.nameField == "Focus"'
wtype -k Return
until_ok 2000 yt_is '.look.sidebar[-1] == "Focus 0"'
made=$(yt_state | jq -r .playlistId)
check "n, Focus, Enter lists a second Focus 0 under PLAYLISTS, beside the first ($(yt_state | jq -c '.look.sidebar[4:]'))" \
  yt_is '.look.sidebar[4] == "Focus 3" and .look.sidebar[-1] == "Focus 0" and .focus == "sidebar"'
check "and opens it, reading p adds a video here ($(yt_state | jq -c '[.view, .playlistId, .empty]'))" \
  yt_is --arg id "$made" '.view == "playlist" and .playlistId == $id and .empty == ["p adds a video here"] and .look.title[1] == "Focus"'
wtype e
until_ok 1000 yt_is --arg id "$made" '.focus == "name" and .naming == $id and .nameField == "Focus"'
wtype -M ctrl a -m ctrl
wtype 'Deep focus'
wtype -k Return
until_ok 2000 yt_is '.look.sidebar[-1] == "Deep focus 0"'
check "e on it, Deep focus, Enter renames it ($(yt_state | jq -c '[.look.sidebar[-1], .look.title[1]]'))" \
  yt_is '.look.sidebar[-1] == "Deep focus 0" and .look.title[1] == "Deep focus" and .focus == "sidebar"'
wtype x
until_ok 1000 yt_is '.confirming'
check "x asks Delete Deep focus and its 0 videos? under its row, the list beside dimmed ($(yt_state | jq -c '[.confirm, .dimmed]'))" \
  yt_is '.confirm == ["Delete Deep focus and its 0 videos?", "y delete", "esc keep"] and .dimmed'
check "Paper frames the question in its red accent ($(yt_state | jq -c .confirmLook))" yt_is '.confirmLook == {"border": "#c8381e", "cut": false, "mark": ""}'
legacy_theme blueprint >/dev/null
until_ok 3000 status_theme blueprint
blueprint_frame() { yt_is '.confirmLook == {"border": "#ffb547", "cut": false, "mark": "!"}'; }
until_ok 3000 blueprint_frame
check "Blueprint frames it in amber with its ! mark ($(yt_state | jq -c .confirmLook))" blueprint_frame
legacy_theme paper >/dev/null
until_ok 3000 status_theme paper
wtype j
sleep 0.3
check "while it asks, j moves nothing" yt_is --arg id "$made" '.playlistId == $id and .confirming'
wtype -k Escape
until_ok 1000 yt_is '.confirming == false'
check "Esc keeps it ($(yt_state | jq -c '[.confirm, .dimmed, .look.sidebar[-1]]'))" \
  yt_is --arg id "$made" '.confirm == null and (.dimmed | not) and .look.sidebar[-1] == "Deep focus 0" and .playlistId == $id'
wtype x
until_ok 1000 yt_is '.confirming'
wtype y
until_ok 2000 yt_is '.look.sidebar[-1] != "Deep focus 0"'
check "x then y removes it, and the sidebar moves to the Playlist above ($(yt_state | jq -c '[.look.sidebar[-1], .playlistId]'))" \
  yt_is '(.look.sidebar | map(select(startswith("Deep focus"))) | length) == 0 and .playlistId == "pl3"'
gone_in_store() { jq -e --arg id "$made" '.playlists[$id].deleted == true' "$store" >/dev/null 2>&1; }
until_ok 2000 gone_in_store
check "and the store keeps it as a tombstone" gone_in_store

# The long name's question, in Blueprint's wider face, draws whole: its name cut, its count kept.
legacy_theme blueprint >/dev/null
until_ok 3000 status_theme blueprint
wtype x
until_ok 1000 yt_is '.confirming'
long_asked() { yt_is '(.confirm[0] | endswith("… and its 0 videos?")) and .confirmLook.cut == false'; }
until_ok 2000 long_asked
check "x on the 300-character Playlist asks a question drawn whole, ending and its 0 videos? ($(yt_state | jq -c '[.confirm[0], .confirmLook]'))" long_asked
wtype -k Escape
until_ok 1000 yt_is '.confirming == false'
legacy_theme paper >/dev/null
until_ok 3000 status_theme paper

# A blank name makes nothing, and Esc leaves the field making nothing.
wtype n
until_ok 1000 yt_is '.focus == "name"'
wtype -k Return
until_ok 1000 yt_is '.focus == "sidebar"'
wtype n
until_ok 1000 yt_is '.focus == "name"'
wtype Unsaved
wtype -k Escape
until_ok 1000 yt_is '.focus == "sidebar" and .naming == "" and .nameField == null'
check "a blank name and an Escaped one make no Playlist ($(yt_state | jq -c '.playlists | length'))" yt_is '(.playlists | length) == 3'

# Saved is never renamed or deleted.
wtype k k k k
until_ok 1000 yt_is '.view == "saved"'
wtype e
wtype x
sleep 0.3
check "on Saved, e and x do nothing ($(yt_state | jq -c '{focus, naming, confirming}'))" yt_is '.focus == "sidebar" and .naming == "" and .confirming == false and .view == "saved"'
wtype -k Escape
until_ok 1000 yt_is '.view == "search"'
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
