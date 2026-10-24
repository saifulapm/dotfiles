#!/usr/bin/env bash
# Enter on a title in Dekho's Home opens its Title page: the cursor on the episode next up, later episodes dimmed with their air date, w marking watched, people to open, and each board's look.
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
dekho_pids() {
  local pid
  for pid in $(pgrep -x qs); do
    tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" | grep -qF -- "-p $dekho_qml" && echo "$pid"
  done
  return 0
}
no_dekho_process() { [ -z "$(dekho_pids)" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
ep() { dekho_state | jq -c ".title.episodes[$1]"; }

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
check "it asked the fake for the title, every season's episodes and the backdrop" \
  bash -c "grep -qx 'api title --id 101 --kind tv' '$DOTS_DEV_DIR/dekho.log' && [ \$(grep -c '^api episodes --id 101 -s [1-4]\$' '$DOTS_DEV_DIR/dekho.log') = 4 ] && grep -qx 'api prefetch --size w780 /b101.png' '$DOTS_DEV_DIR/dekho.log'"
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
  dekho_is '.title.cast[0].name == "Lena Hart" and .title.cast[0].lines == 1 and .title.more == "+ 6 · tab to reach, ↵ opens a person"'
check "the 300-character overview with a newline wraps to at most 3 lines, elided, and the episodes stay drawn ($(dekho_state | jq -c '.title.overview | {lines, truncated}'))" \
  dekho_is '.title.overview.lines <= 3 and .title.overview.truncated and (.title.overview.text | test("\n") | not) and .title.episodesShown'
until_ok 3000 dekho_is '.title.backdrop.image'
check "the backdrop the fake prefetched draws in the image's place ($(dekho_state | jq -c .title.backdrop))" dekho_is '.title.backdrop.image and .title.backdrop.placeholder == false'

wtype j
until_ok 1000 dekho_is '.title.cursor == 5'
wtype -k Return
check "Enter on E5, not aired yet, chooses nothing ($(dekho_state | jq -c .chose))" dekho_is '.title.cursor == 5 and .chose == null'
wtype k
until_ok 1000 dekho_is '.title.cursor == 4'
wtype -k Return
until_ok 1000 dekho_is '.chose != null'
check "Enter on E4, next up, chooses it for a release ($(dekho_state | jq -c .chose))" dekho_is '.chose == {"season": 3, "episode": 4}'

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
check "Enter on a crew name opens that person ($(dekho_state | jq -c .person))" dekho_is '.person == 1001'
wtype f
until_ok 1000 dekho_is '.filter != null'
check "f asks Browse for this title's kind, genre and language ($(dekho_state | jq -c .filter))" dekho_is '.filter == {"kind": "tv", "genre": "Drama", "language": "English"}'

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
check "esc goes back to Home with its cursor where it was ($(dekho_state | jq -c '[.page, .focus]'))" dekho_is '.page == "home" and .focus == {"row": "series", "col": 1}'

# Harbour Lights, the first trending series, has no backdrop.
wtype h
until_ok 1000 dekho_is '.focus.col == 0'
wtype -k Return
until_ok 3000 title_loaded
check "a title whose backdrop is null draws Paper's hatched placeholder in its place ($(dekho_state | jq -c '[.title.name, .title.backdrop]'))" \
  dekho_is '.title.name == "Harbour Lights" and .title.backdrop.placeholder and .title.backdrop.width > 0 and .title.backdrop.height > 0 and .title.backdrop.image == false and .title.look.hatch'
wtype /
until_ok 1000 dekho_is '.page == "home" and .search.focused'
check "/ goes to Home's search field ($(dekho_state | jq -c '[.page, .search.focused]'))" dekho_is '.page == "home" and .search.focused'
wtype -k Escape
until_ok 1000 dekho_is '.search.focused == false'

# Each board's own detail, on The Long Tide's page.
wtype l
until_ok 1000 dekho_is '.focus.col == 1'
wtype -k Return
until_ok 3000 title_loaded
check "paper: an aired date is set in Instrument Serif italic, as the Paper board sets it ($(dekho_state | jq -c '.title.look | {datedFont, datedItalic}'))" \
  dekho_is '.title.look.datedFont == "Instrument Serif" and .title.look.datedItalic and .title.episodes[4].font == "Maple Mono"'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: season tabs are rounded 10 px and the tag reads next up, as the Artboard board draws them ($(dekho_state | jq -c '[.title.look.tabRadius, .title.episodes[3].tag]'))" \
  dekho_is '.title.look.tabRadius == 10 and .title.episodes[3].tag == "next up" and .title.count == "3 of 8 watched"'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the tag reads [NEXT UP] and a date to come AIRS, as the Blueprint board writes them ($(dekho_state | jq -c '[.title.episodes[3].tag, .title.episodes[4].date, .title.count]'))" \
  dekho_is --arg airs "${airs^^}" '.title.episodes[3].tag == "[NEXT UP]" and .title.episodes[4].date == $airs and .title.count == "3 OF 8 WATCHED"'
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
