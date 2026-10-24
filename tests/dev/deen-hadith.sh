#!/usr/bin/env bash
# Deen's Hadith: with no corpus, opening Deen starts the download, which the tab draws and a cut leaves kept for r to resume; then search lists the hits and the right pane shows the cursored one.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log
calls=$DOTS_DEV_DIR/deen.log
bukhari1_ar=$(jq -r '.hits[0].hadith.ar' "$repo/dev/deen/hadith-search-intentions---limit-40.json")

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
hadith() { deen_state | jq -c ".hadith | $1"; }
hadith_is() { deen_state | jq -e ".hadith | $1" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
# The App's own qs, found by its command line, never by pgrep -f, which matches this shell too.
deen_pids() {
  local pid
  for pid in $(pgrep -x qs); do
    tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" | grep -qF -- "-p $deen_qml" && echo "$pid"
  done
  return 0
}
no_deen_process() { [ -z "$(deen_pids)" ]; }
# The fake execs the fetch script, so the App's fetch child is a bash running it.
fetch_pids() {
  local pid
  for pid in $(pgrep -x bash); do
    tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" | grep -qF -- "hadith-fetch---json.sh" && echo "$pid"
  done
  return 0
}
fetches() { grep -cx 'hadith fetch --json' "$calls" 2>/dev/null; }
fetches_are() { [ "$(fetches)" = "$1" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_deen() { niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"; }

# No corpus yet, and the fake's download is cut at 38 MB.
touch "$DOTS_DEV_DIR/deen-hadith-cut"
in_theme paper
# Esc while the fetch runs ends it with the window; the fetch is Deen's child, never left behind.
open_deen
until_ok 5000 deen_up
until_ok 2000 eval '[ -n "$(fetch_pids)" ]'
running_pid=$(fetch_pids | head -1)
wtype -k Shift_L
wtype -k Escape
until_ok 3000 no_deen_process
until_ok 3000 eval '[ ! -d "/proc/$running_pid" ]'
check "Esc during the download ends Deen and its running fetch (${running_pid:-none})" \
  eval '[ -n "$running_pid" ] && [ ! -d "/proc/$running_pid" ] && no_deen_process'
rm "$calls"

open_deen
until_ok 5000 deen_up
check "Deen opens one window" deen_up
until_ok 2000 fetches_are 1
check "opening Deen started one hadith fetch --json while Read shows ($(fetches), tab $(deen_state | jq -c .tab))" \
  eval 'fetches_are 1 && deen_is ".tab == \"read\""'

wtype -k Shift_L
wtype -k Tab -k Tab -k Tab
until_ok 1000 deen_is '.tab == "hadith"'
until_ok 2000 hadith_is '.download.percent != "0%" and .download.speed != ""'
check "state 1 draws the download ($(hadith '.download | [.title, .percent, .size, .speed, .left, .saving]'))" \
  hadith_is '.download.shown and .download.title == "Getting the hadith corpus" and (.download.percent | test("^[0-9]+%$")) and (.download.size | test("^[0-9]+ of 124 MB$")) and .download.speed == "6.2 MB/s" and (.download.left | test("^about [0-9]+ s$")) and (.download.saving | endswith("/.local/share/deen/hadith"))'
# Esc ends the App and its download with it, which the next open resumes (#80V1JZ2Q, #V5Z5V6QF).
check "its keys say Esc closes and the next open carries on ($(hadith '.download.keyLine'))" hadith_is '.download.keyLine == "esc closes; the next open carries on"'
check "state 1 says what works meanwhile ($(hadith '.download.meanwhile'))" \
  hadith_is '.download.meanwhile == ["MEANWHILE", "Read, Duas and Prayer work now.", "Hadith search waits for the download."]'
check "still one fetch, the one from the open ($(fetches))" fetches_are 1
fetch_pid=$(fetch_pids | head -1)
check "the fetch runs as a child of Deen's qs (pid ${fetch_pid:-none})" test -n "$fetch_pid"

wtype -k Tab -k Tab
until_ok 1000 deen_is '.tab == "read"'
check "Tab moves on to Read while the download runs (fetch ${fetch_pid:-none} alive)" eval 'deen_is ".tab == \"read\"" && [ -n "$fetch_pid" ] && [ -d "/proc/$fetch_pid" ]'
until_ok 4000 hadith_is '.download.fail != ""'
wtype -M shift -k Tab -k Tab -m shift
until_ok 1000 deen_is '.tab == "hadith"'
check "state 2 says where it stopped ($(hadith '.download | [.title, .fail, .kept, .savedIn]'))" \
  hadith_is '.download.title == "The download did not finish" and .download.fail == "The connection dropped at 38 of 124 MB. The part already saved is kept, so retrying carries on from there." and .download.kept == "38 MB" and (.download.savedIn | startswith("~/"))'
check "paper: state 2's box is square, ruled in one pixel, its title in the display face ($(hadith '.download.look'))" \
  hadith_is '.download.look.radius == 0 and .download.look.border == 1 and .download.label == "2 · IF IT FAILS"'
in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: state 2's box is rounded 14 and grey, its title in #B4380B ($(hadith '.download.look'))" \
  hadith_is '.download.look.radius == 14 and .download.look.fill == "#f6f7f9" and .download.look.titleColor == "#b4380b" and .download.label == "2 · if it fails"'
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: state 2 reads in brackets and capitals over a dashed rule ($(hadith '.download | [.label, .kept, .keyLine, .look.ruleDashed]'))" \
  hadith_is '.download.label == "[2 · IF IT FAILS]" and .download.look.ruleDashed and .download.keyLine == "[R] RETRY · [ESC] LEAVE"'
in_theme paper
until_ok 3000 deen_is '.voice == "caps"'

rm "$DOTS_DEV_DIR/deen-hadith-cut"
wtype r
until_ok 2000 fetches_are 2
check "r starts a second fetch ($(fetches))" fetches_are 2
until_ok 6000 hadith_is '.ready and .search.foot != "offline"'
check "the download ran to done and search is on ($(hadith '.search | [.shown, .foot]'))" \
  hadith_is '.search.shown and .download.shown == false and .search.foot == "offline · 36,512 narrations"'
check "the field has the keys ($(hadith .focus))" hadith_is '.focus == "field"'

wtype intentions
until_ok 3000 hadith_is '.search.rows | length > 1'
check "typing intentions lists 35 results, Sahih al-Bukhari #1 first graded Sahih ($(hadith '[.search.count, .search.rows[0].name, .search.rows[0].n, .search.rows[0].grade]'))" \
  hadith_is '.search.text == "intentions" and .search.count == "35 results" and .search.rows[0].name == "Sahih al-Bukhari" and .search.rows[0].n == "#1" and .search.rows[0].grade == "Sahih" and .search.rows[0].on and .search.detail.grade == "SAHIH"'
check "the right pane shows it in full with its narrator ($(hadith '.search.detail | [.title, .grade, .narrator, .en[0:40], .arAlign]'))" \
  deen_is --arg ar "$bukhari1_ar" '.hadith | .search.detail.title == "Sahih al-Bukhari · 1" and .search.detail.narrator == "Narrated by '"'"'Umar bin Al-Khattab" and (.search.detail.en | startswith("I heard Allah")) and .search.detail.ar == $ar and .search.detail.arAlign == "right"'
check "intentions ran once the typing stopped ($(grep -c '^hadith search' "$calls") searches)" grep -qx 'hadith search intentions --limit 40' "$calls"
check "paper: the field is a square box ruled in two pixels ($(hadith '.search.look'))" hadith_is '.search.look.fieldRadius == 0 and .search.look.fieldBorder == 2'

wtype -k Down j
until_ok 1000 hadith_is '.search.cursor == 1'
check "↓ moves to the results and j to the second hit ($(hadith '[.focus, .search.cursor, .search.detail.title]'))" \
  hadith_is '.focus == "results" and .search.cursor == 1 and .search.rows[1].on and .search.detail.title == "Sahih al-Bukhari · 1560"'
in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: the field rounds 14, the cursor row fills #EEF1FF ($(hadith '[.search.look.fieldRadius, .search.rows[1].fill, .search.count]'))" \
  hadith_is '.search.look.fieldRadius == 14 and .search.rows[1].fill == "#eef1ff" and .search.rows[1].grade == "Sahih"'
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: the grade and count read in capitals, the pane's rule dashed ($(hadith '[.search.rows[0].grade, .search.count, .search.detail.narrator, .search.look.paneRuleDashed]'))" \
  hadith_is '.search.rows[0].grade == "[SAHIH]" and .search.count == "35 RESULTS" and .search.detail.narrator == "NARRATED BY AL-QASIM BIN MUHAMMAD" and .search.look.paneRuleDashed and .search.foot == "OFFLINE · 36,512 NARRATIONS"'
in_theme paper
until_ok 3000 deen_is '.voice == "caps"'

wtype /
until_ok 1000 hadith_is '.focus == "field" and .search.text == ""'
check "/ clears the field and gives it the keys ($(hadith '[.focus, .search.text]'))" hadith_is '.focus == "field" and .search.text == ""'
wtype forged
wtype -k Return
until_ok 3000 hadith_is '.search.rows | length == 2'
check "the forged hit draws on one line without its controls ($(hadith '.search.rows[0] | [.text, .lineCount, .grade]'))" \
  hadith_is '.search.rows[0].text == "first line second reversed [31m red" and .search.rows[0].lineCount == 1 and .search.rows[0].grade == "Sahih (Al-Albani) · Hasan (Shuaib Al Arnaut)"'
check "the 200-character hit is cut to one line ($(hadith '.search.rows[1] | [.truncated, .lineCount, .grade]'))" \
  hadith_is '.search.rows[1].truncated and .search.rows[1].lineCount == 1 and .search.rows[1].grade == "UNGRADED"'
check "Enter moved to the results, and the forged pane wraps without controls ($(hadith '[.focus, .search.detail.en]'))" \
  hadith_is '.focus == "results" and .search.detail.en == "first line\nsecond reversed[31m red" and .search.detail.narrator == "Narrated by Forged"'

# Esc from the field, which takes typing, still reaches the frame.
fetch_now=$(fetch_pids)
wtype /
until_ok 1000 hadith_is '.focus == "field"'
wtype -k Tab
until_ok 1000 deen_is '.tab == "prayer"'
check "Tab from the field reaches the frame ($(deen_state | jq -c .tab))" deen_is '.tab == "prayer"'
wtype -M shift -k Tab -m shift
until_ok 1000 deen_is '.tab == "hadith" and .hadith.focus == "field"'
wtype -k Escape
until_ok 3000 deen_gone
check "Esc from the field closes the window" deen_gone
until_ok 3000 no_deen_process
check "and no qs with -p .../shell/deen.qml is left" no_deen_process
check "and no fetch script is left (${fetch_pid:-none} ${fetch_now})" eval '[ -z "$(fetch_pids)" ] && [ ! -d "/proc/$fetch_pid" ]'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
