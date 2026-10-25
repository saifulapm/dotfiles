#!/usr/bin/env bash
# Dekho is an App: its desktop entry starts its own qs process with one window in the theme, Home draws search and three rows of titles as its boards do, / finds titles, and Esc ends the process.
{
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
dekho_pids() { session_qs_pids "-p $dekho_qml"; }
no_dekho_process() { [ -z "$(dekho_pids)" ]; }
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }

# The nested shell scans the temp data dir's entries, so the repo's entry goes there for the launcher to list.
cp "$entry" "$DOTS_DEV_DIR/data/applications/dekho.desktop"
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .query == ""'
wtype dekho
until_ok 3000 launcher_is '.query == "dekho" and .results[0] == "Dekho"'
check "the launcher lists Dekho from its desktop entry ($(launcher_state | jq -c '.results[0:2]'))" launcher_is '.results[0] == "Dekho"'
wtype -k Escape
until_ok 2000 launcher_is '.open == false'

# niri spawns the entry's Exec as the launcher would, with the App's stdout and stderr, where qs writes its warnings, in one log.
exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_dekho() { niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"; }

open_dekho
until_ok 5000 dekho_up
check "the entry's Exec ($exec_line) opens one window whose app id is dekho ($(dekho_windows))" dekho_up
check "its first frame came $(dekho_state | jq .firstFrameMs) ms after the process started, under 500" \
  dekho_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
check "its RSS is $(dekho_state | jq .rssKiB) KiB, under 250 MiB" dekho_is '(.rssKiB | type) == "number" and .rssKiB > 0 and .rssKiB < 256000'
check "it opens on Home ($(dekho_state | jq -c .page))" dekho_is '.page == "home"'

until_ok 3000 dekho_is '(.rows.continue | length) == 5 and (.rows.series | length) == 10 and (.rows.movies | length) == 10'
check "continue watching draws 5 titles with their time left ($(dekho_state | jq -c '[.rows.continue[] | .line]'))" \
  dekho_is '[.rows.continue[] | [.title, .line]] == [["The Long Tide", "S3 E4 · 31 min left"], ["Night Ferry", "1h 52 · 40 min left"], ["Ninth Floor", "S1 E7 · 12 min left"], ["Salt Road", "S2 E2 · 44 min left"], ["Copper Hill", "2h 04 · 1h 31 left"]]'
check "and a progress bar each, as far as each has played ($(dekho_state | jq -c '[.rows.continue[] | .progress]'))" \
  dekho_is '[.rows.continue[] | .progress] == [0.4, 0.64, 0.79, 0.08, 0.27]'
check "trending series draws 10 of the fake's 12, each with year and rating ($(dekho_state | jq -c '[.rows.series[] | .line]'))" \
  dekho_is '(.rows.series | length) == 10 and .rows.series[0].title == "Harbour Lights" and .rows.series[0].line == "2026 · ★ 8.4" and all(.rows.series[]; .line | test("^[0-9]{4} · ★ [0-9]\\.[0-9]$"))'
check "trending movies draws 10 of 12, each with year and rating ($(dekho_state | jq -c '[.rows.movies[] | .title][0:3]'))" \
  dekho_is '(.rows.movies | length) == 10 and .rows.movies[0].line == "2026 · ★ 7.8" and .rows.movies[9].title == "Second Light" and all(.rows.movies[]; .line | test("^[0-9]{4} · ★ [0-9]\\.[0-9]$"))'
check "a title with a newline, U+202E and ESC draws on one line, without them ($(dekho_state | jq -c '.rows.series[3]'))" \
  dekho_is '.rows.series[3] | .title == "Low Tide Radio" and .lines == 1'
check "a 300-character title draws on one elided line ($(dekho_state | jq -c '.rows.series[5] | {lines, elided}'))" \
  dekho_is '.rows.series[5] | (.title | length) == 300 and .lines == 1 and .elided'
posters_shown() { dekho_is '[.rows.continue[], .rows.series[], .rows.movies[] | select(.poster.shown)] | length == 19'; }
until_ok 3000 posters_shown
check "each card whose poster the fake holds draws it within 3 s ($(dekho_state | jq -c '[.rows.continue, .rows.series, .rows.movies | map(.poster.shown)]'))" \
  dekho_is '[.rows.continue, .rows.series, .rows.movies | map(.poster.shown)] == [[true, true, false, false, true], [true, true, true, true, true, true, true, false, false, true], [true, true, false, false, true, true, true, true, true, true]]'
check "each draws its own title's poster ($(dekho_state | jq -c '[.rows.continue[0].poster.file, .rows.series[9].poster.file, .rows.movies[4].poster.file]'))" \
  dekho_is '[.rows.continue[0].poster.file, .rows.series[9].poster.file, .rows.movies[4].poster.file] == ["p101.jpg", "p309.jpg", "p404.jpg"]'
check "a null poster and one the fake lacks, as a 404, keep the empty mark ($(dekho_state | jq -c '[.rows.continue[2].poster, .rows.continue[3].poster]'))" \
  dekho_is '[.rows.continue[2], .rows.continue[3], .rows.series[7], .rows.series[8], .rows.movies[2], .rows.movies[3]] | all(.poster.shown == false and .poster.file == "")'
check "each poster decodes at no more than twice its drawn size on the side that fills its place ($(dekho_state | jq -c '.rows.continue[0].poster'))" \
  dekho_is '[.rows.continue[], .rows.series[], .rows.movies[] | .poster | select(.shown)] | length == 19 and all(.decodedWidth > 0 and .decodedHeight > 0 and (([.decodedWidth / .width, .decodedHeight / .height] | min) <= 2))'
check "the App asked the fake for history, both trending kinds and one prefetch per row, each poster once, and nothing else" \
  bash -c "sort '$DOTS_DEV_DIR/dekho.log' | diff - <(printf 'api history --limit 20\napi prefetch --size w342 /p101.jpg /p202.jpg /gone104.jpg /p205.jpg\napi prefetch --size w342 /p300.jpg /p301.jpg /p302.jpg /p303.jpg /p304.jpg /p305.jpg /p306.jpg /gone308.jpg /p309.jpg\napi prefetch --size w342 /p400.jpg /p401.jpg /gone403.jpg /p404.jpg /p405.jpg /p406.jpg /p407.jpg /p408.jpg /p409.jpg\napi trending --kind movie\napi trending --kind tv\n') >/dev/null"

check "the cursor starts on the first title to continue ($(dekho_state | jq -c .focus))" dekho_is '.focus == {"row": "continue", "col": 0}'
wtype jll
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 2}'
check "j then l l moves to the third trending series ($(dekho_state | jq -c .focus))" dekho_is '.focus == {"row": "series", "col": 2}'
wtype -k Return
until_ok 1000 dekho_is '.opened == 302'
check "Enter opens Paper Birds' id ($(dekho_state | jq -c .opened))" dekho_is '.opened == 302'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype lllllll
until_ok 1000 dekho_is '.focus.col == 9'
check "l to the tenth title scrolls it into view ($(dekho_state | jq -c '.rows.series[9].shown'))" dekho_is '.focus.col == 9 and .rows.series[9].shown'
wtype l
check "l past the tenth stays on it" dekho_is '.focus.col == 9'
wtype -k Tab
until_ok 1000 dekho_is '.focus.row == "movies"'
check "tab goes to the next row, trending movies ($(dekho_state | jq -c .focus))" dekho_is '.focus.row == "movies"'
wtype kh
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 8}'
check "k and h move back up and left ($(dekho_state | jq -c .focus))" dekho_is '.focus == {"row": "series", "col": 8}'

wtype /
until_ok 1000 dekho_is '.search.focused'
check "/ puts the cursor in the search field" dekho_is '.search.focused'
wtype tide
until_ok 1000 dekho_is '.search.text == "tide"'
check "typing goes into the field ($(dekho_state | jq -c .search.text))" dekho_is '.search.text == "tide" and .opened == 302'
wtype -k Return
until_ok 3000 dekho_is '(.search.results | length) > 0'
check "Enter finds the fixture's series, The Long Tide, first in the results ($(dekho_state | jq -c '[.search.results[] | .title]'))" \
  dekho_is '(.search.results[0] | del(.poster)) == {"title": "The Long Tide", "line": "2024 · ★ 8.1", "lines": 1, "elided": false, "shown": true} and (.search.results | length) == 3'
check "the results draw the posters already on disk, with no prefetch of their own, and a null one keeps the mark ($(dekho_state | jq -c '[.search.results[] | .poster.file]'))" \
  dekho_is '[.search.results[] | .poster.file] == ["p101.jpg", "p305.jpg", ""] and ([.search.results[] | .poster.shown] == [true, true, false])'
check "and the fake heard no prefetch after the search" bash -c "! sed -n '/^api search tide\$/,\$p' '$DOTS_DEV_DIR/dekho.log' | grep -q '^api prefetch'"
check "the results take the home rows' place ($(dekho_state | jq -c '{focus, shown: .rows.shown}'))" dekho_is '.rows.shown == false and .focus.row == "results"'
check "the fake heard the search for tide" grep -qx 'api search tide' "$DOTS_DEV_DIR/dekho.log"
wtype -k Escape
until_ok 1000 dekho_is '.rows.shown and (.search.results | length) == 0'
check "Esc leaves the results for the home rows, with the window open" dekho_is '.rows.shown and .search.text == "" and (.search.results | length) == 0'

# Each board's own detail, read back from the drawn items while the window stays open.
check "paper: the page heading Home is Instrument Serif, as the Paper board sets it ($(dekho_state | jq -c .look))" \
  dekho_is '.look.homeFont == "Instrument Serif" and .look.rowHead == "CONTINUE WATCHING" and .look.ruleDashed == false'
check "paper: the poster fills its hatched place square ($(dekho_state | jq -c '.rows.continue[0].poster'))" \
  dekho_is '.rows.continue[0].poster | .shown and .radius == 0 and .width == 38 and .height == 56'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: cards are rounded 12 px and headings sentence case, as the Artboard board draws them ($(dekho_state | jq -c .look))" \
  dekho_is '.look.cardRadius == 12 and .look.rowHead == "Continue watching" and .look.homeFont == "Maple Mono"'
check "artboard: the poster is masked to its grey tile's 8 px corners ($(dekho_state | jq -c '.rows.continue[0].poster'))" \
  dekho_is '.rows.continue[0].poster | .shown and .radius == 8 and .width == 36 and .height == 54'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the header rule is dashed and the time left reads MIN LEFT, as the Blueprint board writes it ($(dekho_state | jq -c '[.look, .rows.continue[1].line]'))" \
  dekho_is '.look.ruleDashed and .look.cardRadius == 0 and .rows.continue[1].line == "1h 52 · 40 MIN LEFT"'
check "blueprint: the poster fills its crossed box square, and a null one keeps the cross ($(dekho_state | jq -c '[.rows.continue[0].poster, .rows.continue[2].poster.shown]'))" \
  dekho_is '(.rows.continue[0].poster | .shown and .radius == 0) and .rows.continue[2].poster.shown == false'

wtype -k Escape
until_ok 3000 dekho_gone
check "Esc closes the window" dekho_gone
until_ok 3000 no_dekho_process
check "and within 3 s no qs with -p .../shell/dekho.qml is left" no_dekho_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
