#!/usr/bin/env bash
# Deen's Hadith: with no corpus, opening Deen starts the download, which the tab draws and a cut leaves kept for r to resume; then Enter browses collection, book and narration, Esc goes back up, and / searches from any level.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log
calls=$DOTS_DEV_DIR/deen.log
bukhari1_ar=$(jq -r '.hadiths[0].ar' "$repo/dev/deen/hadith-list-bukhari-1.json")
bukhari1_bn=$(jq -r '.hadiths[0].bn' "$repo/dev/deen/hadith-list-bukhari-1.json")

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
hadith() { deen_state | jq -c ".hadith | $1"; }
hadith_is() { deen_state | jq -e ".hadith | $1" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
deen_pids() { session_qs_pids "-p $deen_qml"; }
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
until_ok 6000 hadith_is '.ready and .foot != "offline"'
check "the download ran to done and the browse is on ($(hadith '[.browse, .foot]'))" \
  hadith_is '.browse and .download.shown == false and .foot == "offline · 36,512 narrations"'

# The Show path: collections, Bukhari's books, book 1's narrations, narration 1.
until_ok 2000 hadith_is '.count == 10'
check "the tab opens on the 10 collections, Bukhari first by its Bangla and English names and count ($(hadith '[.level, .count, .rows[0].text, .focus]'))" \
  hadith_is '.level == "collections" and .count == 10 and .rows[0].text == "সহীহ বুখারী  Sahih al-Bukhari  7583" and .rows[0].on and .focus == "list" and .heading == "COLLECTIONS"'
wtype -k Return
until_ok 2000 hadith_is '.level == "books"'
check "Enter on সহীহ বুখারী lists its books, ১. ওহীর সূচনা first and book 0 last ($(hadith '[.heading, .rows[0].text, .rows[-1].text]'))" \
  hadith_is '.heading == "সহীহ বুখারী" and .count == 4 and .rows[0].text == "১. ওহীর সূচনা  7" and .rows[-1].text == "অন্যান্য  307"'
check "it asked deen for Bukhari's books" grep -qx 'hadith books bukhari' "$calls"
wtype -k Return
until_ok 2000 hadith_is '.level == "narrations"'
check "Enter on book 1 lists its 7 narrations, each one line of Bangla, narration 1's first ($(hadith '[.heading, .count, .rows[0].text[0:40]]'))" \
  deen_is --arg bn "$bukhari1_bn" '.hadith | .heading == "সহীহ বুখারী · ওহীর সূচনা" and .count == 7 and .rows[0].text == $bn and ([.rows[] | .english] | all(. == false))'
check "it asked deen for book 1's list" grep -qx 'hadith list bukhari 1' "$calls"
wtype -k Return
until_ok 2000 hadith_is '.level == "narration"'
pane_is_bukhari1() {
  deen_is --arg bn "$bukhari1_bn" --arg ar "$bukhari1_ar" --arg fam "$1" '.hadith.pane | .shown and .ar == $ar and .meaning == $bn and .reference == "সহীহ বুখারী ১" and (.meaningLabel | ascii_downcase) == "meaning" and .grade == "" and .narrator == "" and .meaningFamily == $fam and .referenceFamily == $fam and .arAlign == "right"'
}
check "Enter opens narration 1: its Arabic, its Bangla and সহীহ বুখারী ১, no English or grade ($(hadith '.pane | [.title, .reference, .meaningLabel, .meaning[0:30], .grade, .narrator]'))" \
  pane_is_bukhari1 "Noto Serif Bengali"
in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard draws the open narration in Noto Sans Bengali ($(hadith '.pane | [.meaningFamily, .meaningLabel, .reference]'))" pane_is_bukhari1 "Noto Sans Bengali"
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint draws the open narration in Noto Sans Bengali ($(hadith '.pane | [.meaningFamily, .meaningLabel, .reference]'))" pane_is_bukhari1 "Noto Sans Bengali"
in_theme paper
until_ok 3000 deen_is '.voice == "caps"'
wtype y
until_ok 1000 hadith_is '.copied != ""'
check "y copies the open narration ($(hadith .copied))" hadith_is '.copied == "copied Sahih al-Bukhari 1"'

wtype -k Escape
until_ok 1000 hadith_is '.level == "narrations"'
check "Esc returns to the narrations, the cursor still on narration 1 ($(hadith '[.level, .cursor, .pane.shown]'))" hadith_is '.level == "narrations" and .cursor == 0 and .pane.shown == false'
wtype -k Escape
until_ok 1000 hadith_is '.level == "books"'
check "Esc returns to the books ($(hadith '[.level, .rows[0].text]'))" hadith_is '.level == "books" and .rows[0].text == "১. ওহীর সূচনা  7"'
wtype -k Escape
until_ok 1000 hadith_is '.level == "collections"'
check "Esc returns to the collections ($(hadith '[.level, .rows[0].text]'))" hadith_is '.level == "collections" and .rows[0].on and .count == 10'
wtype -k Escape
until_ok 3000 deen_gone
check "Esc on the collections closes Deen" deen_gone
until_ok 3000 no_deen_process
check "and no qs with -p .../shell/deen.qml is left" no_deen_process

# The corpus is ready now, so the next open goes straight to the collections.
open_deen
until_ok 5000 deen_up
wtype -k Shift_L
wtype -k Tab -k Tab -k Tab
until_ok 1000 deen_is '.tab == "hadith"'
until_ok 3000 hadith_is '.ready and .count == 10'
check "Deen reopens on the collections ($(hadith '[.level, .count]'))" hadith_is '.level == "collections" and .count == 10'

wtype -k Return
until_ok 2000 hadith_is '.level == "books"'
wtype /
until_ok 1000 hadith_is '.level == "search"'
check "/ from the books opens search with the field's keys ($(hadith '[.level, .focus, .search.shown, .search.text]'))" \
  hadith_is '.level == "search" and .focus == "field" and .search.shown and .search.text == ""'
wtype -k Escape
until_ok 1000 hadith_is '.level == "books"'
check "Esc from search returns to the books ($(hadith '[.level, .focus, .heading, .rows[0].text]'))" \
  hadith_is '.level == "books" and .focus == "list" and .search.shown == false and .heading == "সহীহ বুখারী" and .rows[0].text == "১. ওহীর সূচনা  7"'

wtype /
until_ok 1000 hadith_is '.focus == "field"'
wtype 'নিয়ত'
until_ok 3000 hadith_is '.count == 4'
check "নিয়ত lists Bangla hits, each led by its Bangla reference ($(hadith '[.search.count, .rows[0].text[0:40], [.rows[] | .english]]'))" \
  deen_is --arg bn "$bukhari1_bn" '.hadith | .search.text == "নিয়ত" and .search.count == "4 results" and .rows[0].text == ("সহীহ বুখারী ১  " + $bn) and ([.rows[] | .english] == [false, false, false, true])'
check "the hit without Bangla draws its English under the mark ($(hadith '.rows[3].text'))" \
  hadith_is '.rows[3].text == "সুনান নাসাঈ ৭৫  ENGLISH  It was narrated that '"'"'Umar bin Al-Khattab said: \"The Messenger of Allah (ﷺ) said: '"'"'Actions are only by intentions.'"'"'\""'
check "the first hit opens in the pane as a narration does ($(hadith '.pane | [.reference, .meaningLabel]'))" \
  deen_is --arg bn "$bukhari1_bn" '.hadith.pane | .meaning == $bn and .reference == "সহীহ বুখারী ১" and .meaningLabel == "MEANING"'
check "the search ran on the Bangla word" grep -qx 'hadith search --limit 40 -- নিয়ত' "$calls"
wtype -k Down jjj
until_ok 1000 hadith_is '.cursor == 3'
check "its pane draws the English under ENGLISH with its grade and the Bangla reference ($(hadith '.pane | [.meaningLabel, .meaning[0:30], .grade, .reference, .meaningFamily]'))" \
  hadith_is '.focus == "list" and .pane.meaningLabel == "ENGLISH" and (.pane.meaning | startswith("It was narrated")) and .pane.grade == "SAHIH" and .pane.reference == "সুনান নাসাঈ ৭৫" and (.pane.meaningFamily | test("Bengali") | not)'
check "paper: the field is a square box ruled in two pixels ($(hadith '.look'))" hadith_is '.look.fieldRadius == 0 and .look.fieldBorder == 2'
in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: the field rounds 14, the cursor row fills #EEF1FF, the mark reads English ($(hadith '[.look.fieldRadius, .rows[3].fill, .pane.meaningLabel]'))" \
  hadith_is '.look.fieldRadius == 14 and .rows[3].fill == "#eef1ff" and .pane.meaningLabel == "English" and (.rows[3].text | contains("  English  "))'
in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: the count and foot read in capitals over a dashed pane rule ($(hadith '[.search.count, .foot, .look.paneRuleDashed]'))" \
  hadith_is '.search.count == "4 RESULTS" and .look.paneRuleDashed and .foot == "OFFLINE · 36,512 NARRATIONS"'
in_theme paper
until_ok 3000 deen_is '.voice == "caps"'

wtype /
until_ok 1000 hadith_is '.focus == "field" and .search.text == ""'
check "/ in search clears the field and gives it the keys ($(hadith '[.focus, .search.text]'))" hadith_is '.focus == "field" and .search.text == ""'
wtype forged
wtype -k Return
until_ok 3000 hadith_is '.count == 2'
check "the forged hit draws on one line without its controls ($(hadith '.rows[0] | [.text, .truncated]'))" \
  hadith_is '.rows[0].text == "সুনান আবূ দাউদ ১  ENGLISH  first line second reversed [31m red"'
check "the 200-character hit is cut to one line ($(hadith '.rows[1] | [.truncated]'))" hadith_is '.rows[1].truncated'
check "Enter moved to the list, and the forged pane wraps without controls ($(hadith '[.focus, .pane.meaning, .pane.grade]'))" \
  hadith_is '.focus == "list" and .pane.meaning == "first line\nsecond reversed[31m red" and .pane.narrator == "Narrated by Forged" and .pane.grade == "SAHIH (AL-ALBANI) · HASAN (SHUAIB AL ARNAUT)"'
wtype -k Escape
until_ok 1000 hadith_is '.level == "books"'
wtype -k Escape
until_ok 1000 hadith_is '.level == "collections"'
check "Esc from search, then Esc from the books, is back on the collections ($(hadith '[.level, .search.text]'))" hadith_is '.level == "collections" and .search.text == ""'

# A collection with no Bangla: every Qudsi narration reads in English, marked.
wtype jjjjjjjj
until_ok 1000 hadith_is '.cursor == 8'
wtype -k Return
until_ok 2000 hadith_is '.level == "books"'
wtype -k Return
until_ok 2000 hadith_is '.level == "narrations"'
check "Qudsi's narrations list in English under the mark ($(hadith '[.heading, .rows[0].text]'))" \
  hadith_is '.heading == "চল্লিশ হাদীসে কুদসী · চল্লিশ হাদীসে কুদসী" and ([.rows[] | .english] | all) and (.rows[0].text | startswith("ENGLISH  When Allah decreed the Creation"))'
wtype -k Return
until_ok 1000 hadith_is '.level == "narration"'
check "a Qudsi narration opens in English under ENGLISH with its narrator and Bangla reference ($(hadith '.pane | [.meaningLabel, .meaning[0:30], .narrator, .reference]'))" \
  hadith_is '.pane.meaningLabel == "ENGLISH" and (.pane.meaning | startswith("When Allah decreed")) and .pane.narrator == "Narrated by Abu Hurairah" and .pane.reference == "চল্লিশ হাদীসে কুদসী ১"'
wtype -k Escape -k Escape -k Escape
until_ok 1000 hadith_is '.level == "collections"'

# A long book: the cursor on its last row keeps that row on screen.
wtype kkkkkkkk
until_ok 1000 hadith_is '.cursor == 0'
wtype -k Return
until_ok 2000 hadith_is '.level == "books"'
wtype jj
until_ok 1000 hadith_is '.cursor == 2'
wtype -k Return
until_ok 2000 hadith_is '.level == "narrations" and .count == 40'
wtype "$(printf 'j%.0s' $(seq 39))"
until_ok 3000 hadith_is '.cursor == 39'
check "Bukhari 8's last row is drawn on screen with the cursor on it ($(hadith '[.cursor, (.rows[] | select(.on) | [.index, .inView, .text])]'))" \
  hadith_is '.cursor == 39 and ([.rows[] | select(.on)] | length == 1 and .[0].index == 39 and .[0].inView and .[0].text == "সালাত বিষয়ে বর্ণনা ৩৮৮।")'

# Tab still reaches the frame from the field, and Esc from it goes back, not out.
fetch_now=$(fetch_pids)
wtype /
until_ok 1000 hadith_is '.focus == "field"'
wtype -k Tab
until_ok 1000 deen_is '.tab == "prayer"'
check "Tab from the field reaches the frame ($(deen_state | jq -c .tab))" deen_is '.tab == "prayer"'
wtype -M shift -k Tab -m shift
until_ok 1000 deen_is '.tab == "hadith" and .hadith.focus == "field"'
wtype -k Escape
until_ok 1000 hadith_is '.level == "narrations"'
check "Esc from the field returns to the narrations ($(hadith '[.level, .cursor]'))" hadith_is '.level == "narrations" and .cursor == 39'
wtype -k Escape -k Escape -k Escape
until_ok 3000 deen_gone
check "Esc up through the books and collections closes the window" deen_gone
until_ok 3000 no_deen_process
check "and no qs with -p .../shell/deen.qml is left" no_deen_process
check "and no fetch script is left (${fetch_pid:-none} ${fetch_now})" eval '[ -z "$(fetch_pids)" ] && [ ! -d "/proc/$fetch_pid" ]'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
