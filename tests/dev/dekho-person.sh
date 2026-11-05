#!/usr/bin/env bash
# Enter on a crew name in Dekho's Title page opens their Person page: portrait or its placeholder, life years, birthplace, biography, credits split into directing, acting and writing with the role beside each; tab moves between the groups, Enter opens a title, f opens Browse with the person as a chip; the board's look.
{
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/dekho.log
calls=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
person_loaded() { dekho_is '.page == "person" and .personPage.ready'; }
# The drawn credits, not their headings.
credits() { dekho_state | jq -c "[.personPage.lines[] | select(.head | not) | $1]"; }
heads() { dekho_state | jq -c '[.personPage.lines[] | select(.head) | .text]'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide, then the crew: Mara Lindqvist, its director.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "crew"'
wtype -k Return
until_ok 3000 person_loaded
check "Enter on the director opens her Person page, the Title page's person still in state ($(dekho_state | jq -c '[.page, .person, .personPage.tmdbId]'))" \
  dekho_is '.page == "person" and .person == 1001 and .personPage.tmdbId == 1001'
check "it asked the fake for her page and her portrait" \
  bash -c "grep -qx 'api person --id 1001' '$calls' && grep -qx 'api prefetch --size w185 /m1001.png' '$calls'"
check "her name, with a newline, U+202E and ESC in it, draws on one line without them, in the header and the side ($(dekho_state | jq -c '[.personPage.name, .personPage.headerName]'))" \
  dekho_is '.personPage.name == "Mara Lindqvist" and .personPage.nameLines == 1 and .personPage.headerName == "Mara Lindqvist"'
check "the years read 1978 –, the birthplace Gothenburg, Sweden ($(dekho_state | jq -c '[.personPage.subline, .personPage.place]'))" \
  dekho_is '.personPage.subline == "1978 – · Directing · Acting · Writing" and .personPage.place == "Gothenburg, Sweden"'
check "the long biography with a newline wraps inside its box in the 300 px side, never pushing the credits off ($(dekho_state | jq -c '.personPage.bio'))" \
  dekho_is '.personPage.bio.lines > 5 and (.personPage.bio.text | test("\n") | not) and .personPage.bio.fits and .personPage.bio.width < .personPage.bio.panel and .personPage.creditsShown'
until_ok 3000 dekho_is '.personPage.portrait.image'
check "the portrait the fake prefetched draws in the placeholder's place ($(dekho_state | jq -c .personPage.portrait))" \
  dekho_is '.personPage.portrait.image and .personPage.portrait.placeholder == false'
check "three groups draw with their headings and counts ($(heads))" \
  dekho_is '[.personPage.lines[] | select(.head) | [.text, .count]] == [["Directing", "3"], ["Acting", "3"], ["Writing", "2"]] and .personPage.count == "Filmography · 8 credits"'
check "each credit has its role beside it, an actor's part after \"as\" ($(credits '.role'))" \
  dekho_is '[.personPage.lines[] | select(.head | not) | [.group, .title, .role, .vote]] == [["directing", "The Long Tide", "Director", "★ 8.1"], ["directing", "Night Ferry", "Director", "★ 7.3"], ["directing", "Seven Stations", "Director", "★ 7.6"], ["acting", "A Quiet Verdict", "as Judge Hale", "★ 7.8"], ["acting", "Salt Road", "as Nora Vell", "★ 7.4"], ["acting", "Copper Hill", "as Dr. Anya Rask", "★ 7.1"], ["writing", "Night Ferry", "Screenplay", "★ 7.3"], ["writing", "The Long Tide", "Creator", "★ 8.1"]] and ([.personPage.lines[] | select(.head | not) | .titleLines, .roleLines] | all(. == 1))'
check "the cursor starts on her first credit, The Long Tide, directing ($(dekho_state | jq -c '[.personPage.cursor, .personPage.group]'))" \
  dekho_is '.personPage.cursor == 0 and .personPage.group == "directing"'
posters() { dekho_state | jq -c '[.personPage.lines[] | select(.head | not) | .poster.file]'; }
until_ok 3000 dekho_is '[.personPage.lines[] | select(.head | not) | select(.poster.shown)] | length == 6'
check "each credit with a poster the fake holds draws its own in the 18 x 27 place, under directing, acting and writing ($(posters))" \
  dekho_is '[.personPage.lines[] | select(.head | not) | [.group, .title, .poster.file]] == [["directing", "The Long Tide", "c101.jpg"], ["directing", "Night Ferry", "c102.jpg"], ["directing", "Seven Stations", ""], ["acting", "A Quiet Verdict", ""], ["acting", "Salt Road", "c105.jpg"], ["acting", "Copper Hill", "c106.jpg"], ["writing", "Night Ferry", "c102.jpg"], ["writing", "The Long Tide", "c101.jpg"]] and ([.personPage.lines[] | select(.head | not) | .poster | select(.shown)] | all(.width == 18 and .height == 27 and .radius == 4))'
check "a null poster (Seven Stations) and a gone one (A Quiet Verdict) keep the empty mark ($(dekho_state | jq -c '[.personPage.lines[] | select(.head | not) | select(.poster.shown | not) | [.title, .poster.shown]]'))" \
  dekho_is '[.personPage.lines[] | select(.head | not) | select(.poster.shown | not) | .title] == ["Seven Stations", "A Quiet Verdict"]'
check "a credit poster decodes at no more than twice its drawn 18 x 27 ($(dekho_state | jq -c '.personPage.lines[1].poster'))" \
  dekho_is '[.personPage.lines[] | select(.head | not) | .poster | select(.shown)] | length == 6 and all(.decodedWidth > 0 and .decodedHeight > 0 and (([.decodedWidth / .width, .decodedHeight / .height] | min) <= 2))'
check "all the credits' posters came from one prefetch call, each path once, the gone one asked and left out" \
  bash -c "[ \$(grep -c '/c101.jpg' '$calls') = 1 ] && grep -qx 'api prefetch --size w342 /c101.jpg /c102.jpg /gone104.jpg /c105.jpg /c106.jpg' '$calls'"

wtype -k Tab
until_ok 1000 dekho_is '.personPage.group == "acting"'
check "tab moves the cursor to the next group, on A Quiet Verdict ($(dekho_state | jq -c '[.personPage.cursor, .personPage.group]'))" \
  dekho_is '.personPage.cursor == 3 and .personPage.group == "acting" and ([.personPage.lines[] | select(.cursor)] | map(.title)) == ["A Quiet Verdict"]'
wtype -k Tab
until_ok 1000 dekho_is '.personPage.group == "writing"'
check "tab again reaches writing, on Night Ferry ($(dekho_state | jq -c '[.personPage.cursor, .personPage.group]'))" \
  dekho_is '.personPage.cursor == 6 and ([.personPage.lines[] | select(.cursor)] | map(.title)) == ["Night Ferry"]'

wtype -k Return
until_ok 1000 dekho_is '.page == "title"'
check "Enter on that credit opens Night Ferry's Title page ($(dekho_state | jq -c '[.page, .opened]'))" dekho_is '.page == "title" and .opened == 102'
wtype -k Escape
until_ok 1000 dekho_is '.page == "person"'
check "esc goes back to her page with the cursor where it was ($(dekho_state | jq -c '[.page, .personPage.cursor]'))" dekho_is '.page == "person" and .personPage.cursor == 6 and .personPage.name == "Mara Lindqvist"'

wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.chips | length) == 1'
check "f opens Browse with her as the only chip ($(dekho_state | jq -c '[.browse.chips[].text, .browse.prefilled]'))" \
  dekho_is '[.browse.chips[].text] == ["Mara Lindqvist"]'
check "and the fake heard --person 1001 for both kinds" \
  bash -c "grep -qx 'api discover --kind movie --person 1001' '$calls' && grep -qx 'api discover --kind tv --person 1001' '$calls'"
wtype -k Escape
until_ok 1000 dekho_is '.page == "person"'

# Tomas Eze, the writer: no portrait, dead, one group.
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
check "esc from her page comes back to The Long Tide, not the credit opened from it, with the cursor on her ($(dekho_state | jq -c '[.title.tmdbId, .title.zone]'))" \
  dekho_is '.title.tmdbId == 101 and .title.zone == "crew"'
wtype l
wtype -k Return
until_ok 3000 person_loaded
until_ok 3000 dekho_is '.personPage.tmdbId == 1002'
check "a person with no portrait draws the placeholder with TE ($(dekho_state | jq -c .personPage.portrait))" \
  dekho_is '.personPage.portrait.placeholder and .personPage.portrait.image == false and .personPage.portrait.initials == "TE" and .personPage.portrait.width == 120 and .personPage.portrait.height == 120'
check "the years of the dead read 1931 – 2004, with no birthplace or biography and one group ($(dekho_state | jq -c '[.personPage.subline, .personPage.place, .personPage.bio.text]'))" \
  dekho_is '.personPage.subline == "1931 – 2004 · Writing" and .personPage.place == "" and .personPage.bio.text == "" and ([.personPage.lines[] | select(.head) | .text] == ["Writing"])'
check "the portrait is a circle and the credit row rounded 10 px, the key and the kind in lower case ($(dekho_state | jq -c '[.personPage.look.portraitRadius, .personPage.look.rowRadius, .personPage.button, .personPage.lines[1].kind]'))" \
  dekho_is '.personPage.look.portraitRadius == 60 and .personPage.look.rowRadius == 10 and .personPage.button == "f filter the library by Tomas" and .personPage.lines[1].kind == "film"'

wtype /
until_ok 1000 dekho_is '.page == "home" and .search.focused'
check "/ goes to Home's search field ($(dekho_state | jq -c '[.page, .search.focused]'))" dekho_is '.page == "home" and .search.focused'
wtype -k Escape
until_ok 1000 dekho_is '.search.focused == false'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Home closes the window" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
