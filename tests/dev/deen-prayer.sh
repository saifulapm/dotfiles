#!/usr/bin/env bash
# Deen's Prayer lists a day's five prayers with the past ones dimmed and the next one marked with its countdown, moves a day with the arrows, returns with t, refreshes with r, and counts to tomorrow's Fajr after Isha, in each theme's own look.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
prayer() { deen_state | jq -c ".prayer | ${1:-.}"; }
prayer_is() { deen_state | jq -e ".prayer | $1" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
deen_pids() { session_qs_pids "-p $deen_qml"; }
no_deen_process() { [ -z "$(deen_pids)" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
asked() { grep -cxF -- "prayer $1" "$DOTS_DEV_DIR/deen.log" 2>/dev/null || true; }
any_asked() { grep -c '^prayer' "$DOTS_DEV_DIR/deen.log" 2>/dev/null || true; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
# The fake backend answers from dev/deen, and DOTS_DEEN_NOW pins the minute the page counts from.
open_deen() { niri msg action spawn -- sh -c "DOTS_DEEN=$repo/bin/dev-fake-deen DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_DEEN_NOW=$1 exec $exec_line >>'$log' 2>&1"; }
close_deen() {
  wtype -k Escape
  until_ok 3000 deen_gone
  until_ok 3000 no_deen_process
}
to_prayer() {
  until_ok 5000 deen_up
  wtype -k Shift_L
  wtype -k Tab -k Tab -k Tab -k Tab
  until_ok 5000 prayer_is '.rows | length > 0'
}

in_theme paper
open_deen 2026-10-23T14:32
until_ok 5000 deen_up
check "the day is not asked for before the section shows ($(any_asked) calls)" test -z "$(any_asked | grep -v '^0$')"
to_prayer
check "Tab four times reaches Prayer" deen_is '.tab == "prayer" and .heading == "Prayer"'
check "the five rows read the day's times ($(prayer '.rows | map(.name + " " + .time)'))" \
  prayer_is '.rows | map(.name + " " + .time) == ["Fajr 04:43","Dhuhr 11:43","Asr 15:50","Maghrib 17:26","Isha 18:42"]'
check "Fajr and Dhuhr draw dimmed and the rest do not ($(prayer '.rows | map(.nameColor)'))" \
  prayer_is '.rows | map(.nameColor) == ["#575653","#575653","#faf6ec","#1c1915","#1c1915"] and .[0].timeColor == "#575653" and .[4].timeColor == "#1c1915"'
check "Asr is the next row, tagged next and Hanafi, and no other row is ($(prayer '.rows | map(.tag)'))" \
  prayer_is '.rows | map(.tag) == ["","","next · Hanafi","",""] and (map(.next) == [false,false,true,false,false])'
check "the countdown reads $(prayer .headline) and $(prayer .at)" \
  prayer_is '.label == "NEXT PRAYER" and .headline == "Asr in 1 h 18 min" and .at == "15:50 · now 14:32"'
check "the city, the date line, the Asr line and the method read as the board's ($(prayer '[.city, .date]'))" \
  prayer_is '.city == "Dhaka" and .date == "Friday 23 October 2026 · sunrise 05:59" and .asr == "Asr: Hanafi (shadow twice its length)" and .method == "Method: University of Islamic Sciences, Karachi · aladhan, cached for the month"'
check "the keys read the board's five ($(prayer .keys))" prayer_is '.keys == [["←/→","OTHER DAY"],["T","TODAY"],["R","REFRESH"],["TAB","SECTION"],["ESC","CLOSE"]]'

wtype -k Right
until_ok 3000 prayer_is '.rows[0].time == "04:44"'
check "Right shows 24 October's times and asks the backend for that day ($(prayer '.rows | map(.time)'))" \
  prayer_is '.rows | map(.time) == ["04:44","11:43","15:49","17:25","18:41"]'
check "the fake logged prayer --date 2026-10-24" test "$(asked '--date 2026-10-24')" -ge 1
check "another day dims nothing and marks no next, only Asr keeps its tag ($(prayer '.rows | map(.nameColor)'))" \
  prayer_is '(.rows | map(.nameColor) | unique == ["#1c1915"]) and (.rows | map(.tag) == ["","","Hanafi","",""])'
check "the right side says the day is not today and gives that day's date ($(prayer '[.label, .headline, .date]'))" \
  prayer_is '.label == "NOT TODAY" and .headline == "Tomorrow" and .at == "" and .date == "Saturday 24 October 2026 · sunrise 06:00"'
wtype -k t
until_ok 3000 prayer_is '.rows[0].time == "04:43"'
check "t returns to the 23rd, next and countdown back ($(prayer '[.rows[2].time, .headline]'))" \
  prayer_is '.rows[2].next and .headline == "Asr in 1 h 18 min" and (.date | startswith("Friday 23 October 2026"))'
check "and asks for it again ($(asked '--date 2026-10-23'))" test "$(asked '--date 2026-10-23')" = 2

wtype r
until_ok 3000 prayer_is '.method | endswith("· aladhan")'
check "r asks for the day again with --refresh ($(asked '--date 2026-10-23 --refresh'))" test "$(asked '--date 2026-10-23 --refresh')" = 1
check "and the method line follows the fresh answer ($(prayer .method))" prayer_is '.method == "Method: University of Islamic Sciences, Karachi · aladhan"'

wtype -k Left -k Left
until_ok 3000 prayer_is '.city | startswith("Forged")'
check "the forged city draws on one line without its controls ($(prayer '[.city, .cityLines]'))" \
  prayer_is '.city == "Forged city [31mred" and .cityLines == 1 and (.city | test("[\u0000-\u001f‪-‮]") | not)'
check "two days back shows the 21st with no dimming ($(prayer '[.headline, .date]'))" prayer_is '.headline == "2 days ago" and (.rows | map(.next) | any | not)'
wtype -k t
until_ok 3000 prayer_is '.city == "Dhaka"'

# The 25th has no fixture, which is what a month never fetched and offline looks like.
wtype -k Right -k Right
until_ok 3000 prayer_is '.failed != ""'
check "an answer of error draws that the times need the network, with r to retry ($(prayer '[.failed, .retry]'))" \
  prayer_is '.failed == "Prayer times need the network once a month" and .retry == "R TO RETRY" and .rows == []'
wtype r
until_ok 3000 test "$(asked '--date 2026-10-25 --refresh')" = 1
check "r on the failed day asks again with --refresh" test "$(asked '--date 2026-10-25 --refresh')" = 1
wtype -k t
until_ok 3000 prayer_is '.failed == "" and (.rows | length) == 5'

# Each theme's board detail, with the 23rd at 14:32 shown.
check "paper: a square ink row for the next prayer, ruled boxes for the rest ($(prayer '.rows[2], .rows[3]'))" \
  prayer_is '.rows[2].fill == "#1c1915" and .rows[2].radius == 0 and .rows[2].border == 0 and .rows[2].tagRadius == 0 and .rows[2].tagFill == "#faf6ec" and .rows[3].fill == "#00000000" and .rows[3].border == 1 and (.look.dividerDashed | not)'
in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
until_ok 3000 prayer_is '.rows[0].radius == 14'
check "artboard: sentence-case label, plain keys ($(prayer '[.label, .keys[0]]'))" prayer_is '.label == "Next prayer" and .keys[0] == ["←/→","other day"] and .keys[4] == ["esc","close"]'
check "artboard: the next row is a dark 14 px card with a white 8 px tag ($(prayer '.rows[2]'))" \
  prayer_is '.rows[2].fill == "#15171b" and .rows[2].radius == 14 and .rows[2].tagFill == "#ffffff" and .rows[2].tagRadius == 8 and .rows[2].nameColor == "#ffffff"'
check "artboard: the other rows are grey cards, the past ones dimmed ($(prayer '.rows[0], .rows[3]'))" \
  prayer_is '.rows[3].fill == "#f6f7f9" and .rows[3].radius == 14 and .rows[3].border == 0 and .rows[0].nameColor == "#57606a" and .rows[3].nameColor == "#15171b"'
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
until_ok 3000 prayer_is '.look.dividerDashed'
check "blueprint: capitals, an ISO date and a bracketed tag ($(prayer '[.date, .asr, .rows[2].tag]'))" \
  prayer_is '.date == "FRIDAY 2026-10-23 · SUNRISE 05:59" and .asr == "ASR: HANAFI (SHADOW TWICE ITS LENGTH)" and .method == "METHOD: UNIVERSITY OF ISLAMIC SCIENCES, KARACHI · ALADHAN, CACHED FOR THE MONTH" and .rows[2].tag == "[NEXT · HANAFI]"'
check "blueprint: the next row is a square accent block with a bare tag ($(prayer '.rows[2]'))" \
  prayer_is '.rows[2].fill == "#7fe3f0" and .rows[2].radius == 0 and .rows[2].tagFill == "#00000000" and .rows[2].nameColor == "#0a1526"'
check "blueprint: ruled rows, the past ones dimmed, dashed rules ($(prayer '.rows[0], .rows[3]'))" \
  prayer_is '.rows[3].border == 1 and .rows[3].radius == 0 and .rows[0].nameColor == "#80a4c2" and .rows[3].nameColor == "#d6f4f8" and .look.dividerDashed and .look.ruleDashed'
check "blueprint: the keys are bracketed ($(prayer .keys))" prayer_is '.keys == [["[←/→]","OTHER DAY"],["[T]","TODAY"],["[R]","REFRESH"],["[TAB]","SECTION"],["[ESC]","CLOSE"]]'

close_deen
check "Esc closes the window" deen_gone
check "and within 3 s no qs with -p .../shell/deen.qml is left" no_deen_process

# After Isha the next prayer is tomorrow's Fajr.
in_theme paper
before=$(asked '--date 2026-10-24')
open_deen 2026-10-23T19:10
to_prayer
until_ok 3000 prayer_is '.headline != ""'
check "at 19:10 the page asks for 24 October ($(asked '--date 2026-10-24') calls, $before before)" test "$(asked '--date 2026-10-24')" -gt "$before"
check "and counts down to its Fajr ($(prayer '[.headline, .at]'))" prayer_is '.label == "NEXT PRAYER" and .headline == "Fajr in 9 h 34 min" and .at == "04:44 · now 19:10"'
check "every row of the day is dimmed and none is next ($(prayer '.rows | map(.nameColor)'))" \
  prayer_is '(.rows | map(.nameColor) | unique == ["#575653"]) and (.rows | map(.next) | any | not)'
close_deen
check "Esc closes the window and no deen qs is left" no_deen_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
