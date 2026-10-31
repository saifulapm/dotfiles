#!/usr/bin/env bash
# YouTube is an App: its desktop entry starts its own qs process with one window on Search, drawn as each theme's board draws it, its keys move between the field, the list and the sidebar, and Esc on Search ends the process.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
entry=$repo/home/dot_local/share/applications/youtube.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/youtube.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
no_yt_process() { [ -z "$(session_qs_pids "-p $yt_qml")" ]; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }

# The nested shell scans the temp data dir's entries, so the repo's entry goes there for the launcher to list.
cp "$entry" "$DOTS_DEV_DIR/data/applications/youtube.desktop"
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .query == ""'
wtype youtube
until_ok 3000 launcher_is '.query == "youtube" and .results[0] == "YouTube"'
check "the launcher lists YouTube from its desktop entry ($(launcher_state | jq -c '.results[0:2]'))" launcher_is '.results[0] == "YouTube"'
wtype -k Escape
until_ok 2000 launcher_is '.open == false'

# niri spawns the entry's Exec as the launcher would, with the App's stdout and stderr, where qs writes its warnings, in one log.
exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
check "the entry's Exec ($exec_line) opens one window whose app id is youtube ($(yt_windows))" yt_up
check "its first frame came $(yt_state | jq .firstFrameMs) ms after the process started, under 500" \
  yt_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
check "its RSS is $(yt_state | jq .rssKiB) KiB, under 250 MiB" yt_is '(.rssKiB | type) == "number" and .rssKiB > 0 and .rssKiB < 256000'
check "it opens on Search with the list focused and no rows ($(yt_state | jq -c '{view, focus, rows}'))" \
  yt_is '.view == "search" and .focus == "list" and .rows == []'

wtype /
until_ok 1000 yt_is '.focus == "field"'
check "/ puts the cursor in the search field ($(yt_state | jq -c .focus))" yt_is '.focus == "field"'
wtype m
until_ok 1000 yt_is '.query == "m"'
check "m types into the field and changes nothing else ($(yt_state | jq -c '{query, view, focus}'))" yt_is '.query == "m" and .view == "search" and .focus == "field"'
wtype -k Escape
until_ok 1000 yt_is '.focus == "list"'
check "Esc in the field returns to the list with the window open ($(yt_state | jq -c '{focus, view}'))" yt_is '.focus == "list" and .view == "search" and .query == "m"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
check "Tab moves to the sidebar ($(yt_state | jq -c .focus))" yt_is '.focus == "sidebar"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'
check "Tab again returns to the list ($(yt_state | jq -c .focus))" yt_is '.focus == "list"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j
until_ok 1000 yt_is '.view == "saved"'
check "j in the sidebar opens Saved, which draws its empty text ($(yt_state | jq -c '{view, empty, title: .look.title}'))" \
  yt_is '.view == "saved" and .focus == "sidebar" and .empty == ["Nothing saved yet", "s saves a video"] and .look.title[1] == "Saved"'
# Saved draws no field, so / from there goes to Search's.
wtype /
until_ok 1000 yt_is '.focus == "field"'
check "/ on Saved opens Search with the cursor in its field ($(yt_state | jq -c '{view, focus}'))" yt_is '.view == "search" and .focus == "field"'
wtype -k Escape
until_ok 1000 yt_is '.focus == "list"'
wtype -k Tab
until_ok 1000 yt_is '.focus == "sidebar"'
wtype j
until_ok 1000 yt_is '.view == "saved"'
wtype k
until_ok 1000 yt_is '.view == "search"'
check "k goes back up to Search, which draws no empty text ($(yt_state | jq -c '{view, empty}'))" yt_is '.view == "search" and .empty == []'
wtype -k Tab
until_ok 1000 yt_is '.focus == "list"'

# Each board's own detail, read back from the drawn items while the window stays open.
in_theme paper
until_ok 3000 yt_is '.voice == "caps"'
check "paper: a small caps label over a serif view name, from the launcher at its right ($(yt_state | jq -c '.look | {title, viewFont}'))" \
  yt_is '.look.title == ["YOUTUBE", "Search", "from the launcher"] and .look.viewFont == "Instrument Serif"'
check "paper: the legend reads in tracked caps ($(yt_state | jq -c '.look.legend[0:3]'))" \
  yt_is '.look.legend == ["J/K MOVE", "↵ PLAY VIDEO", "M PLAY AUDIO", "A ADD TO QUEUE", "S SAVE", "P ADD TO PLAYLIST", "D/D DOWNLOAD AUDIO/VIDEO", "/ SEARCH", "TAB SIDEBAR", "ESC BACK"]'
check "paper: a square frame and ruled field, solid rules, an empty now-playing line with repeat off ($(yt_state | jq -c '.look | {frameRadius, fieldRadius, ruleDashed, nowPlaying, chips}'))" \
  yt_is '.look.frameRadius == 0 and .look.fieldRadius == 0 and .look.ruleDashed == false and .look.nowPlaying == ["", "repeat off"] and .look.chips == ["Videos", "Playlists", "Channels"] and .look.placeholder == "Search YouTube"'
check "paper: the sidebar lists Search, Saved and History, PLAYLISTS and n makes one ($(yt_state | jq -c '.look.sidebar'))" \
  yt_is '.look.sidebar == ["Search", "Saved 0", "History 0", "PLAYLISTS", "n makes one"]'
in_theme artboard
until_ok 3000 yt_is '.voice == "plain"'
check "artboard: a YouTube pill beside a bold view name and a from the launcher pill ($(yt_state | jq -c '.look | {title, viewFont, viewBold, pills}'))" \
  yt_is '.look.title == ["YouTube", "Search", "from the launcher"] and .look.viewFont == "Maple Mono" and .look.viewBold and .look.pills == [true, true]'
check "artboard: the legend reads in lower case chips ($(yt_state | jq -c '.look.legend[0:3]'))" \
  yt_is '.look.legend == ["j/k move", "↵ play video", "m play audio", "a add to queue", "s save", "p add to playlist", "d/D download audio/video", "/ search", "tab sidebar", "esc back"]'
check "artboard: the frame and field are rounded 14 px and the rules are solid ($(yt_state | jq -c '.look | {frameRadius, fieldRadius, ruleDashed, results}'))" \
  yt_is '.look.frameRadius == 14 and .look.fieldRadius == 14 and .look.ruleDashed == false and .look.results == ["Results", "0"]'
in_theme blueprint
until_ok 3000 yt_is '.voice == "bracket"'
check "blueprint: YOUTUBE, a bold view name and FROM THE LAUNCHER ($(yt_state | jq -c '.look | {title, viewBold}'))" \
  yt_is '.look.title == ["YOUTUBE", "Search", "FROM THE LAUNCHER"] and .look.viewBold and .look.pills == [false, false]'
check "blueprint: the legend reads [KEY] WORD in upper case ($(yt_state | jq -c '.look.legend[0:3]'))" \
  yt_is '.look.legend == ["[J/K] MOVE", "[↵] PLAY VIDEO", "[M] PLAY AUDIO", "[A] ADD TO QUEUE", "[S] SAVE", "[P] ADD TO PLAYLIST", "[D/⇧D] DOWNLOAD AUDIO / VIDEO", "[/] SEARCH", "[TAB] SIDEBAR", "[ESC] BACK"]'
check "blueprint: square corners, dashed rules, caps chips and REPEAT OFF ($(yt_state | jq -c '.look | {frameRadius, fieldRadius, ruleDashed, chips, nowPlaying, hint}'))" \
  yt_is '.look.frameRadius == 0 and .look.fieldRadius == 0 and .look.ruleDashed and .look.chips == ["VIDEOS", "PLAYLISTS", "CHANNELS"] and .look.nowPlaying == ["", "REPEAT OFF"] and .look.hint == "[/]"'
check "blueprint: the sidebar opens with LIBRARY over Search ($(yt_state | jq -c '.look.sidebar[0:2]'))" \
  yt_is '.look.sidebar[0:2] == ["LIBRARY", "Search"]'

check "it is still on Search with the list focused before Esc ($(yt_state | jq -c '{view, focus}'))" yt_is '.view == "search" and .focus == "list"'
wtype -k Escape
until_ok 3000 yt_gone
check "Esc on Search closes the window" yt_gone
until_ok 2000 no_yt_process
check "and within 2 s no qs with -p .../shell/youtube.qml is left" no_yt_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
