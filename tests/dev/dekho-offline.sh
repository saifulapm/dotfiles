#!/usr/bin/env bash
# With TMDB unreachable Dekho's Home draws the rows the backend saved, marked with the date it saved them, search is off, and r retries until fresh rows replace them.
{
# Nothing here presses Enter on a title, but a Return that played by mistake would start a unit on this machine's real user manager, so the run has a unit name of its own, stopped at the end.
export DOTS_DEKHO_UNIT=dekho-offline-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  rm -rf "$work"
}
log=$work/dekho.log
fake_log=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
trending_calls() { grep -c '^api trending --kind tv$' "$fake_log"; }

# The fake's saved copy is two days old, so the boards' dates are two days back; the minute may roll while the check runs, so the notice may carry any of the last three.
day=$(LC_ALL=C date -d '2 days ago' '+%-d %b')
stamps=()
for back in 0 1 2; do stamps+=("$(LC_ALL=C date -d "2 days ago - $back minutes" '+%-d %b %H:%M')"); done
notice_is() { dekho_is --arg a "TMDB is unreachable. Showing saved rows from ${stamps[0]}." --arg b "TMDB is unreachable. Showing saved rows from ${stamps[1]}." --arg c "TMDB is unreachable. Showing saved rows from ${stamps[2]}." '.offline.notice as $n | $n == $a or $n == $b or $n == $c'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
posters_on() { dekho_is "[.rows.continue[], .rows.series[], .rows.movies[] | select(.poster.shown)] | length == $1"; }

# A warm run first, with TMDB up, puts the rows' posters on disk.
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 posters_on 19
check "with TMDB up, the rows draw the 19 posters the fake holds ($(dekho_state | jq -c '[.rows.continue[], .rows.series[], .rows.movies[] | select(.poster.shown)] | length'))" posters_on 19
wtype -k Escape
until_ok 3000 dekho_gone

touch "$DOTS_DEV_DIR/dekho-offline"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
# Each row still holds a poster the fake lacks, so its prefetch answers only after the fake's 4 s timeout: posters within 3 s come from the disk.
until_ok 3000 posters_on 17
check "with TMDB blocked, reopening draws the posters already on disk for the saved rows within 3 s, before any prefetch answers ($(dekho_state | jq -c '[.rows.series, .rows.movies | map(.poster.shown)]'))" \
  dekho_is '[.rows.continue, .rows.series, .rows.movies | map(.poster.shown)] == [[true, true, false, false, true], [true, true, true, true, true, true, true, false, false], [true, true, false, false, true, true, true, true, true]]'

check "Home draws the saved trending series, 9 of the copy's titles ($(dekho_state | jq -c '[.rows.series[] | .title][0:3]'))" \
  dekho_is '(.rows.series | length) == 9 and (.rows.movies | length) == 9 and (.rows.series[0] | del(.poster)) == {"title": "Harbour Lights", "line": "2026 · ★ 8.4", "lines": 1, "elided": false, "shown": true}'
check "each saved row is marked with the day it was saved, saved $day ($(dekho_state | jq -c .marks))" \
  dekho_is --arg m "saved $day" '.marks.series == $m and .marks.movies == $m'
check "the notice reads \"TMDB is unreachable. Showing saved rows from ${stamps[0]}.\" ($(dekho_state | jq -c .offline.notice))" notice_is
check "and offers the retry key, r retry ($(dekho_state | jq -c .offline.retry))" dekho_is '.offline.shown and .offline.retry == "r retry"'
check "continue watching still draws its 5 titles from this machine's history ($(dekho_state | jq -c '[.marks.continue, (.rows.continue | length)]'))" \
  dekho_is '(.rows.continue | length) == 5 and .marks.continue == "from this machine" and .rows.continue[0].title == "The Long Tide"'
check "the key strip offers r, move, open and close and no search, in Paper's capitals ($(dekho_state | jq -c .offline.keys))" \
  dekho_is '.offline.keys == [["R", "RETRY"], ["H/J/K/L", "MOVE"], ["↵", "OPEN"], ["ESC", "CLOSE"]]'
check "search is off: the field is replaced by \"Search needs TMDB\" ($(dekho_state | jq -c .offline.search))" \
  dekho_is '.offline.search == {"text": "Search needs TMDB", "field": false}'
wtype /
sleep 0.3
check "/ does not focus search, and the cursor stays where it was ($(dekho_state | jq -c '[.search.focused, .focus]'))" \
  dekho_is '.search.focused == false and .focus == {"row": "continue", "col": 0}'
check "the fake heard no search" bash -c "! grep -q '^api search' '$fake_log'"

check "paper: the notice is ruled in ink, its ! mark a square ink block, as the Paper board draws them ($(dekho_state | jq -c .offline.look))" \
  dekho_is '.offline.look as $l | $l.noticeFill == "" and ($l.markFill | ascii_downcase) == "#1c1915" and $l.markRadius == 0 and $l.noticeRadius == 0'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain" and .marks.series == "saved '"$day"'"'
check "artboard: the notice is a rounded 12 px peach block with a round ! mark, as the Artboard board draws it ($(dekho_state | jq -c .offline.look))" \
  dekho_is '.offline.look as $l | ($l.noticeFill | ascii_downcase) == "#fff1e8" and $l.noticeRadius == 12 and $l.markRadius == 9 and ($l.markFill | ascii_downcase) == "#b4380b"'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket" and .marks.series == "SAVED '"${day^^}"'"'
check "blueprint: the mark and retry are capitals, SAVED ${day^^} and [R] RETRY, the ! mark amber, as the Blueprint board writes them ($(dekho_state | jq -c '[.marks.series, .offline.retry, .offline.look.markFill]'))" \
  dekho_is '.marks.series == "SAVED '"${day^^}"'" and .offline.retry == "[R] RETRY" and (.offline.look.markFill | ascii_downcase) == "#ffb547"'

# A retry while TMDB is still down keeps the saved rows.
before=$(trending_calls)
wtype r
until_ok 3000 bash -c "[ \$(grep -c '^api trending --kind tv\$' '$fake_log') = $((before + 1)) ]"
sleep 0.5
check "r with TMDB still down asks again and keeps the saved rows and the notice ($(trending_calls) trending calls)" \
  dekho_is '.offline.shown and (.rows.series | length) == 9'

# TMDB comes back.
rm -f "$DOTS_DEV_DIR/dekho-offline"
before=$(trending_calls)
wtype r
until_ok 3000 dekho_is '(.rows.series | length) == 10 and (.rows.movies | length) == 10'
check "r with TMDB back: the fake heard a new trending call ($before, then $(trending_calls))" test "$(trending_calls)" -gt "$before"
check "the fresh rows replace the saved ones, 10 titles each ($(dekho_state | jq -c '[(.rows.series | length), (.rows.movies | length)]'))" \
  dekho_is '(.rows.series | length) == 10 and (.rows.movies | length) == 10'
check "the saved marks and the notice are gone ($(dekho_state | jq -c '[.marks, .offline.shown]'))" \
  dekho_is '.offline.shown == false and .marks.series == "THIS WEEK" and .marks.movies == "THIS WEEK" and .marks.continue == "5"'
wtype /
until_ok 1000 dekho_is '.search.focused'
check "and search is back: / focuses the field ($(dekho_state | jq -c .offline.search))" dekho_is '.search.focused and .offline.search.field'

wtype -k Escape
wtype -k Escape
until_ok 3000 dekho_gone
check "Esc closes the window" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
