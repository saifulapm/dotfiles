#!/usr/bin/env bash
# Dekho's Title page under the meta line: the title's tagline on one elided line, and TMDB, IMDb and Homepage links that Tab, h/l, Enter and a click open in Chromium.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

chromium_log=$DOTS_DEV_DIR/chromium.log
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
film_loaded() { dekho_is '.page == "title" and .title.name == "A Quiet Verdict" and (.title.crew | length) == 3'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
links() { dekho_state | jq -c '[.title.links[] | [.text, .url]]'; }
opened() { grep -cx "$1" "$chromium_log" 2>/dev/null; }
opened_once() { [ "$(opened "$1")" = 1 ]; }

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide, the second trending series: a tagline, TMDB and IMDb, and no homepage.
click_on series:1
until_ok 3000 title_loaded
check "The Long Tide draws its tagline on one line ($(dekho_state | jq -c .title.tagline))" \
  dekho_is '.title.tagline == {"text": "The water remembers.", "lines": 1, "truncated": false, "shown": true}'
check "it links TMDB under /tv/ and IMDb, and no Homepage ($(links))" \
  dekho_is '[.title.links[] | [.kind, .text, .url]] == [["tmdb", "TMDB", "https://www.themoviedb.org/tv/101"], ["imdb", "IMDb", "https://www.imdb.com/title/tt0000101"]] and all(.title.links[]; .lines == 1)'
check "the page opens on the episodes, so no link is focused ($(dekho_state | jq -c '[.title.zone, [.title.links[].focused]]'))" \
  dekho_is '.title.zone == "episodes" and ([.title.links[].focused] == [false, false])'

# Episodes, crew, cast and More like this come before the buttons, which the links follow.
wtype -k Tab
wtype -k Tab
wtype -k Tab
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "links"'
check "tab from the buttons reaches the links, TMDB focused ($(dekho_state | jq -c '[.title.zone, .title.links[] | [.kind, .focused]]'))" \
  dekho_is '.title.zone == "links" and ([.title.links[] | [.kind, .focused]] == [["tmdb", true], ["imdb", false]]) and ([.title.buttons[].focused] | any | not)'
wtype l
until_ok 1000 dekho_is '.title.links[1].focused'
check "l moves to IMDb ($(dekho_state | jq -c '[.title.links[] | [.kind, .focused]]'))" dekho_is '[.title.links[] | [.kind, .focused]] == [["tmdb", false], ["imdb", true]]'
wtype l
sleep 0.3
check "l on the last link stays on it" dekho_is '.title.links[1].focused'
wtype -k Return
until_ok 3000 opened_once https://www.imdb.com/title/tt0000101
check "Enter on IMDb opened its page in Chromium ($(cat "$chromium_log"))" opened_once https://www.imdb.com/title/tt0000101
wtype h
until_ok 1000 dekho_is '.title.links[0].focused'
check "h moves back to TMDB" dekho_is '[.title.links[] | .focused] == [true, false]'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "seasons"'
check "tab from the links reaches the seasons ($(dekho_state | jq -c .title.zone))" dekho_is '.title.zone == "seasons"'

click_on title-link:tmdb
until_ok 3000 opened_once https://www.themoviedb.org/tv/101
check "a click on TMDB opened its page in Chromium and moved the cursor onto it ($(cat "$chromium_log"))" \
  bash -c "[ \$(grep -cx 'https://www.themoviedb.org/tv/101' '$chromium_log') = 1 ] && [ \$(wc -l <'$chromium_log') = 2 ]"
check "the cursor is on the TMDB link ($(dekho_state | jq -c '[.title.zone, .title.links[0].focused]'))" dekho_is '.title.zone == "links" and .title.links[0].focused'

# Each board's own words: Paper sets them as written, Artboard too, Blueprint upper-cases them.
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: the links read TMDB and IMDb and the tagline as written ($(links))" \
  dekho_is '[.title.links[].text] == ["TMDB", "IMDb"] and .title.tagline.text == "The water remembers." and .title.tagline.shown'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the links read TMDB and IMDB, upper-cased ($(links))" dekho_is '[.title.links[].text] == ["TMDB", "IMDB"] and .title.tagline.shown and .title.tagline.lines == 1'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'
check "paper: the links read TMDB and IMDb ($(links))" dekho_is '[.title.links[].text] == ["TMDB", "IMDb"]'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

# Harbour Lights, the first trending series, forges a tagline, a javascript: homepage and no imdb id.
click_on series:0
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.name == "Harbour Lights" and .title.tagline.shown'
check "a tagline with a newline, U+202E and ESC and 300 more characters draws on one elided line without them ($(dekho_state | jq -c '.title.tagline | {text: .text[0:60], lines, truncated, shown}'))" \
  dekho_is '.title.tagline | .shown and .lines == 1 and .truncated and (.text | length) > 300 and (.text | startswith("Every harbour keeps a light burning")) and (.text | test("[\u0001-\u001f\u007f‮]") | not)'
check "a javascript: homepage and a missing imdb id show only TMDB ($(links))" \
  dekho_is '[.title.links[] | [.kind, .url]] == [["tmdb", "https://www.themoviedb.org/tv/300"]]'
for theme in artboard blueprint; do
  in_theme "$theme"
  until_ok 3000 dekho_is '.voice != "caps"'
  check "$theme: the forged tagline still draws on one line and no Homepage link ($(dekho_state | jq -c '[.title.tagline.lines, [.title.links[].kind]]'))" \
    dekho_is '.title.tagline.shown and .title.tagline.lines == 1 and ([.title.links[].kind] == ["tmdb"])'
done
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

# A Quiet Verdict, the first trending film: no tagline, and a Homepage link last.
wtype jhh
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 0}'
wtype -k Return
until_ok 3000 film_loaded
check "a film with an empty tagline draws no tagline line ($(dekho_state | jq -c .title.tagline))" dekho_is '.title.tagline.shown == false and .title.tagline.text == ""'
check "it links TMDB under /movie/, IMDb and its Homepage ($(links))" \
  dekho_is '[.title.links[] | [.kind, .text, .url]] == [["tmdb", "TMDB", "https://www.themoviedb.org/movie/400"], ["imdb", "IMDb", "https://www.imdb.com/title/tt0000400"], ["homepage", "Homepage", "https://example.org/a-quiet-verdict"]]'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "links"'
wtype ll
until_ok 1000 dekho_is '.title.links[2].focused'
wtype -k Return
until_ok 3000 opened_once https://example.org/a-quiet-verdict
check "Enter on Homepage opened the film's own site in Chromium ($(tail -1 "$chromium_log"))" opened_once https://example.org/a-quiet-verdict
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the film's links read TMDB, IMDB and HOMEPAGE, and still no tagline ($(links))" \
  dekho_is '[.title.links[].text] == ["TMDB", "IMDB", "HOMEPAGE"] and .title.tagline.shown == false'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 900 <<<"$errs")}" test -z "$errs"

exit "$fails"
}
