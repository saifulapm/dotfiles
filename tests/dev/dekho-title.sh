#!/usr/bin/env bash
# Enter on a title in Dekho's Home opens its Title page: the cursor on the episode next up, later episodes dimmed with their air date, w marking watched, people to open, and each board's look.
{
# A Return that played by mistake would start a unit on this machine's real user manager, so it gets this run's own name, stopped at the end.
export DOTS_DEKHO_UNIT=dekho-play-title-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  rm -rf "$work"
}
log=$work/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
dekho_pids() { session_qs_pids "-p $dekho_qml"; }
no_dekho_process() { [ -z "$(dekho_pids)" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
ep() { dekho_state | jq -c ".title.episodes[$1]"; }
layout() { dekho_state | jq -c .title.layout; }
# A film's page draws the series page's header band (its rule's y), and its block starts the same distance under it.
film_layout_is() {
  dekho_is --argjson s "$1" '.title.layout as $f | ($f.header | type) == "number" and $f.header > 0 and $f.header == $s.header and $f.blockTop == $s.blockTop and $f.blockTop > $f.header and $f.blockTop - $f.header <= 24'
}

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
check "its first frame came $(dekho_state | jq .firstFrameMs) ms after the process started, under 500, with the Title page built beside Home" \
  dekho_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide is the second trending series.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
check "Enter on The Long Tide opens its Title page ($(dekho_state | jq -c '[.page, .title.name]'))" dekho_is '.page == "title" and .title.name == "The Long Tide" and .title.lines == 1'
# Home's Continue watching row already holds The Long Tide's poster at w342, so the page asks only for its backdrop.
check "it asked the fake for the title, every season's episodes and the backdrop at w780" \
  bash -c "grep -qx 'api title --id 101 --kind tv' '$DOTS_DEV_DIR/dekho.log' && [ \$(grep -c '^api episodes --id 101 -s [1-4]\$' '$DOTS_DEV_DIR/dekho.log') = 4 ] && grep -qx 'api prefetch --size w780 /b101.png' '$DOTS_DEV_DIR/dekho.log'"
faces_asked() { [ "$(grep -c '^api prefetch --size w185 ' "$DOTS_DEV_DIR/dekho.log")" = 1 ] && grep -qx 'api prefetch --size w185 /f101-1001.jpg /gone101-1003.jpg /f101-2001.jpg /f101-2002.jpg /f101-2003.jpg /f101-2004.jpg /f101-2005.jpg /f101-2006.jpg /f101-2007.jpg /f101-2008.jpg /f101-2009.jpg /f101-2010.jpg /f101-2011.jpg /f101-2012.jpg /f101-2013.jpg /f101-2014.jpg /f101-2015.jpg /f101-2016.jpg /f101-2017.jpg /f101-2018.jpg /f101-2019.jpg /f101-2020.jpg' "$DOTS_DEV_DIR/dekho.log"; }
until_ok 3000 faces_asked
check "the crew's and the cast's faces came from one w185 prefetch, the null one left out ($(grep '^api prefetch --size w185 ' "$DOTS_DEV_DIR/dekho.log" | head -c 120))" faces_asked
stills_asked() {
  for s in 1 2 4; do grep -qx "api prefetch --size w342 /s101-$s-1.jpg /s101-$s-2.jpg /s101-$s-3.jpg /s101-$s-4.jpg /s101-$s-5.jpg /s101-$s-6.jpg /s101-$s-7.jpg /s101-$s-8.jpg" "$DOTS_DEV_DIR/dekho.log" || return 1; done
  grep -qx 'api prefetch --size w342 /s101-3-1.jpg /gone101-3-3.jpg /s101-3-4.jpg /s101-3-5.jpg /s101-3-6.jpg /s101-3-7.jpg /s101-3-8.jpg' "$DOTS_DEV_DIR/dekho.log" && [ "$(grep -c '^api prefetch --size w342 /s101-' "$DOTS_DEV_DIR/dekho.log")" = 4 ]
}
until_ok 3000 stills_asked
check "each season's stills came from one w342 prefetch of its own ($(grep -c '^api prefetch --size w342 /s101-' "$DOTS_DEV_DIR/dekho.log") calls)" stills_asked
check "the season tab opens on S3, the season holding next up, past S1 and S2 all watched ($(dekho_state | jq -c '.title.tabs'))" \
  dekho_is '.title.season == 3 and .title.tabs == [{"text": "S1", "current": false}, {"text": "S2", "current": false}, {"text": "S3", "current": true}, {"text": "S4", "current": false}]'
check "the cursor is on E4, the first aired episode not watched, and its row reads NEXT UP ($(ep 3))" \
  dekho_is '.title.cursor == 4 and .title.episodes[3].cursor and .title.episodes[3].tag == "NEXT UP" and ([.title.episodes[] | select(.tag != "")] | length) == 1'
check "the count reads 3 of 8 watched ($(dekho_state | jq -c .title.count))" dekho_is '.title.count == "3 of 8 watched"'
airs="airs $(LC_ALL=C date -d '+7 days' '+%-d %b')"
check "E5, a week from today, reads \"$airs\" and is drawn dimmed in the muted colour ($(ep 4))" \
  dekho_is --arg airs "$airs" '.title.episodes[4] as $e | $e.date == $airs and ($e.color | ascii_downcase) == (.title.look.muted | ascii_downcase) and (.title.episodes[0].color | ascii_downcase) == (.title.look.ink | ascii_downcase) and $e.watched == false'
check "the chips read the genres and the original language ($(dekho_state | jq -c '[.title.chips[].text]'))" \
  dekho_is '[.title.chips[].text] == ["Drama", "Mystery", "English"]'
check "the crew is the director, writer and composer, without the executive producer ($(dekho_state | jq -c '[.title.crew[] | [.name, .role]]'))" \
  dekho_is '[.title.crew[] | [.name, .role]] == [["Mara Lindqvist", "director"], ["Tomas Eze", "writer"], ["Ingrid Sol", "composer"]]'
check "an episode name with a newline, U+202E and ESC draws on one line without them ($(ep 1))" \
  dekho_is '.title.episodes[1].name == "The Tide Book" and .title.episodes[1].lines == 1'
check "a cast name with a newline, U+202E and ESC draws on one line without them ($(dekho_state | jq -c '.title.cast[0]'))" \
  dekho_is '.title.cast[0].name == "Lena Hart" and .title.cast[0].lines == 1 and .title.more == "+ 17 · tab to reach, ↵ opens a person"'
check "the 300-character overview with a newline wraps to at most 3 lines, elided, and the episodes stay drawn ($(dekho_state | jq -c '.title.overview | {lines, truncated}'))" \
  dekho_is '.title.overview.lines <= 3 and .title.overview.truncated and (.title.overview.text | test("\n") | not) and .title.episodesShown'
until_ok 3000 dekho_is '.title.slot.shown'
check "the poster draws in the picture's place, not the backdrop ($(dekho_state | jq -c .title.slot))" \
  dekho_is '.title.slot | .shown and .file == "p101.jpg" and .width == 220 and .height == 300 and .radius == 0'
until_ok 3000 dekho_is '.title.crew[0].face.shown and .title.cast[2].face.shown'
check "each crew chip draws its person's face in its 20 px square, a null and a gone profile keep the mark ($(dekho_state | jq -c '[.title.crew[].face | [.shown, .file]]'))" \
  dekho_is '[.title.crew[].face | [.shown, .file, .width, .height]] == [[true, "f101-1001.jpg", 20, 20], [false, "", 20, 20], [false, "", 20, 20]]'
check "each cast chip draws its own person's face ($(dekho_state | jq -c '[.title.cast[].face.file]'))" \
  dekho_is '[.title.cast[].face | [.shown, .file]] == [[true, "f101-2001.jpg"], [true, "f101-2002.jpg"], [true, "f101-2003.jpg"]]'
until_ok 3000 dekho_is '.title.episodes[0].still.shown and .title.episodes[7].still.shown'
check "each episode row draws its still at 40x22, a null and a gone still keep the mark ($(dekho_state | jq -c '[.title.episodes[0:4][].still | [.shown, .file]]'))" \
  dekho_is '[.title.episodes[0:4][].still | [.shown, .file, .width, .height]] == [[true, "s101-3-1.jpg", 40, 22], [false, "", 40, 22], [false, "", 40, 22], [true, "s101-3-4.jpg", 40, 22]]'
check "the slot's poster, each face and each still decode at no more than twice their drawn size on the side that fills the place ($(dekho_state | jq -c '[.title.slot, .title.cast[0].face, .title.episodes[0].still] | map([.width, .height, .decodedWidth, .decodedHeight])'))" \
  dekho_is '[.title.slot, (.title.crew[], .title.cast[] | .face), (.title.episodes[] | .still) | select(.shown)] | length >= 6 and all(.decodedWidth > 0 and .decodedHeight > 0 and (([.decodedWidth / .width, .decodedHeight / .height] | min) <= 2))'

wtype j
until_ok 1000 dekho_is '.title.cursor == 5'
wtype -k Return
check "Enter on E5, not aired yet, chooses nothing ($(dekho_state | jq -c .chose))" dekho_is '.title.cursor == 5 and .chose == null'
wtype k
until_ok 1000 dekho_is '.title.cursor == 4'
wtype -k Return
until_ok 1000 dekho_is '.chose != null'
check "Enter on E4, next up, chooses it for a release ($(dekho_state | jq -c .chose))" dekho_is '.chose == {"season": 3, "episode": 4}'
# Enter opened the release list over the page; esc closes it before the Title page's own keys.
wtype -k Escape
until_ok 1000 dekho_is '.page == "title" and .releases.mode == ""'

wtype w
until_ok 3000 dekho_is '.title.episodes[3].watched'
check "w marks E4 watched through the backend and redraws its mark and the count ($(dekho_state | jq -c '[.title.episodes[3].watched, .title.count]'))" \
  dekho_is '.title.episodes[3].watched and .title.count == "4 of 8 watched"'
check "the fake heard the mark for S3 E4" grep -qx 'api watched --id 101 -s 3 -e 4' "$DOTS_DEV_DIR/dekho.log"
wtype w
until_ok 3000 dekho_is '.title.episodes[3].watched == false'
check "w again unmarks it ($(dekho_state | jq -c '[.title.episodes[3].watched, .title.count]'))" \
  dekho_is '.title.episodes[3].watched == false and .title.count == "3 of 8 watched" and .title.episodes[3].tag == "NEXT UP"'

wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "crew"'
check "tab from the episodes reaches the crew, on Mara Lindqvist ($(dekho_state | jq -c '[.title.zone, .title.crew[0].focused]'))" dekho_is '.title.zone == "crew" and .title.crew[0].focused'
wtype -k Return
until_ok 1000 dekho_is '.person != null'
check "Enter on a crew name opens that person ($(dekho_state | jq -c '[.page, .person]'))" dekho_is '.page == "person" and .person == 1001'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
wtype f
until_ok 1000 dekho_is '.filter != null'
check "f asks Browse for this title's kind, genre and language ($(dekho_state | jq -c .filter))" dekho_is '.filter == {"kind": "tv", "genre": "Drama", "language": "English"}'
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
check "esc goes back to Home with its cursor where it was ($(dekho_state | jq -c '[.page, .focus]'))" dekho_is '.page == "home" and .focus == {"row": "series", "col": 1}'

# Harbour Lights, the first trending series, has a backdrop and no poster.
wtype h
until_ok 1000 dekho_is '.focus.col == 0'
wtype -k Return
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.slot.shown'
check "a title whose poster is null draws its backdrop in the picture's place ($(dekho_state | jq -c '[.title.name, .title.slot]'))" \
  dekho_is '.title.name == "Harbour Lights" and (.title.slot | .shown and .file == "b300.jpg" and .width == 220 and .height == 300)'
check "it asked for that backdrop at w780" grep -qx 'api prefetch --size w780 /b300.jpg' "$DOTS_DEV_DIR/dekho.log"
wtype /
until_ok 1000 dekho_is '.page == "home" and .search.focused'
check "/ goes to Home's search field ($(dekho_state | jq -c '[.page, .search.focused]'))" dekho_is '.page == "home" and .search.focused'
wtype -k Escape
until_ok 1000 dekho_is '.search.focused == false'

# Each board's own detail, on The Long Tide's page; leaving the search put the cursor back on Continue watching, where Enter would play.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
check "paper: an aired date is set in Instrument Serif italic, as the Paper board sets it ($(dekho_state | jq -c '.title.look | {datedFont, datedItalic}'))" \
  dekho_is '.title.look.datedFont == "Instrument Serif" and .title.look.datedItalic and .title.episodes[4].font == "Maple Mono"'
check "paper: the poster fills the hatched place square ($(dekho_state | jq -c .title.slot))" dekho_is '.title.slot | .shown and .file == "p101.jpg" and .radius == 0'
series_paper=$(layout)
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: the poster is masked to the grey tile's 14 px corners ($(dekho_state | jq -c .title.slot))" dekho_is '.title.slot | .shown and .file == "p101.jpg" and .radius == 14'
check "artboard: season tabs are rounded 10 px and the tag reads next up, as the Artboard board draws them ($(dekho_state | jq -c '[.title.look.tabRadius, .title.episodes[3].tag]'))" \
  dekho_is '.title.look.tabRadius == 10 and .title.episodes[3].tag == "next up" and .title.count == "3 of 8 watched"'
series_artboard=$(layout)
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the tag reads [NEXT UP] and a date to come AIRS, as the Blueprint board writes them ($(dekho_state | jq -c '[.title.episodes[3].tag, .title.episodes[4].date, .title.count]'))" \
  dekho_is --arg airs "${airs^^}" '.title.episodes[3].tag == "[NEXT UP]" and .title.episodes[4].date == $airs and .title.count == "3 OF 8 WATCHED"'
check "blueprint: the poster fills the crossed box square ($(dekho_state | jq -c .title.slot))" dekho_is '.title.slot | .shown and .file == "p101.jpg" and .radius == 0'
series_blueprint=$(layout)
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

# A Quiet Verdict, the first trending film, has no seasons or episodes; its crew comes only with the detail.
wtype jhh
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 0}'
wtype -k Return
until_ok 3000 dekho_is '.page == "title" and .title.name == "A Quiet Verdict" and (.title.crew | length) == 3'
check "blueprint: a film's page draws the series page's header and its block under it (film $(layout), series $series_blueprint)" film_layout_is "$series_blueprint"
check "blueprint: a title with neither poster nor backdrop keeps the crossed box ($(dekho_state | jq -c '[.title.slot, .title.look.cross]'))" \
  dekho_is '(.title.slot | .shown == false and .file == "" and .width == 220 and .height == 300) and .title.look.cross'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: a film's page draws the series page's header and its block under it (film $(layout), series $series_artboard)" film_layout_is "$series_artboard"
check "artboard: a title with neither poster nor backdrop keeps the grey tile and its picture icon ($(dekho_state | jq -c '[.title.slot, .title.look.icon]'))" \
  dekho_is '(.title.slot | .shown == false and .file == "") and .title.look.icon'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'
check "paper: a film's page draws the series page's header and its block under it (film $(layout), series $series_paper)" film_layout_is "$series_paper"
check "paper: a title with neither poster nor backdrop keeps the hatch ($(dekho_state | jq -c '[.title.slot, .title.look.hatch]'))" \
  dekho_is '(.title.slot | .shown == false and .file == "") and .title.look.hatch'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'

# Paper Birds (302) and then Low Tide Radio (303), neither opened before, with every prefetch answer 2 s late: Paper Birds' answers land while Low Tide Radio is open.
echo 2 >"$DOTS_DEV_DIR/dekho-slow-prefetch"
wtype kll
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 2}'
wtype -k Return
until_ok 3000 dekho_is '.title.tmdbId == 302 and .title.season > 0 and (.title.episodes | length) > 0'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype l
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 3}'
wtype -k Return
until_ok 3000 dekho_is '.title.tmdbId == 303 and .title.season > 0 and (.title.episodes | length) > 0'
check "Paper Birds' prefetch had not answered when Low Tide Radio opened" bash -c "! grep -qs f302- '$DOTS_DEV_DIR/dekho-slow.log'"
# Every 50 ms for 5 s, the files Low Tide Radio's slot, chips and rows draw.
drawn_files() { dekho_state | jq -c '.title | [.tmdbId, .slot.file, (.crew[], .cast[] | .face.file), (.episodes[] | .still.file)]'; }
samples=$work/samples
end=$(($(now_ms) + 5000))
while (($(now_ms) < end)); do
  drawn_files >>"$samples"
  sleep 0.05
done
rm "$DOTS_DEV_DIR/dekho-slow-prefetch"
check "Paper Birds' faces and stills landed while Low Tide Radio was open" bash -c "grep -q f302- '$DOTS_DEV_DIR/dekho-slow.log' && grep -q s302- '$DOTS_DEV_DIR/dekho-slow.log'"
check "Low Tide Radio drew its own poster, faces and stills ($(tail -1 "$samples" | head -c 200))" \
  bash -c "tail -1 '$samples' | jq -e '.[0] == 303 and .[1] == \"p303.jpg\" and .[2] == \"f303-1001.jpg\" and .[5] == \"f303-2001.jpg\" and .[8] == \"s303-3-1.jpg\"' >/dev/null"
check "no sample of Low Tide Radio's page drew a file of Paper Birds ($(wc -l <"$samples") samples$(grep -m1 -oE '[a-z]+302[^"]*' "$samples" | sed 's/^/, /'))" \
  bash -c "[ \$(wc -l <'$samples') -gt 20 ] && ! grep -qE '[a-z]302' '$samples' && ! grep -qv '^\[303,' '$samples'"
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Title, then on Home, closes the window" dekho_gone
until_ok 3000 no_dekho_process
check "and within 3 s no qs with -p .../shell/dekho.qml is left" no_dekho_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
