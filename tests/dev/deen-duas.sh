#!/usr/bin/env bash
# Deen's Duas lists Hisn al-Muslim's chapters, opens a chapter's duas in the pane, steps with n, copies with y, filters with /, and closes with Esc, in each theme's own look.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
duas() { deen_state | jq -c ".duas | ${1:-.}"; }
duas_is() { deen_state | jq -e ".duas | $1" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
deen_pids() { session_qs_pids "-p $deen_qml"; }
no_deen_process() { [ -z "$(deen_pids)" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
# The pane's Arabic with tatweel, harakat and the alef carriers folded as the crate's normalise.rs does.
letters() { node -e 'process.stdout.write(require("fs").readFileSync(0, "utf8").replace(/[ً-ٰٟۖ-ۭـ࣓-ࣿ]/g, "").replace(/[آأإٱ]/g, "ا"))'; }
many() { printf "$1%.0s" $(seq "$2"); }
calls() { cat "$DOTS_DEV_DIR/deen.log" 2>/dev/null | grep -c '^dua list$'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
# The fake backend answers from dev/deen; the App's calls reach it through DOTS_DEEN.
open_deen() { niri msg action spawn -- sh -c "DOTS_DEEN=${1:-$repo/bin/dev-fake-deen} DOTS_DEV_DIR=$DOTS_DEV_DIR exec $exec_line >>'$log' 2>&1"; }

in_theme paper
open_deen
until_ok 5000 deen_up
check "the book is not asked for before the section shows ($(calls) dua list calls)" test "$(calls)" = 0
wtype -k Shift_L
wtype -k Tab -k Tab
until_ok 5000 duas_is '.rows | length > 0'
check "Tab twice reaches Duas" deen_is '.tab == "duas" and .heading == "Duas"'
check "the heading reads the book and its count ($(duas .heading))" duas_is '.heading == "HISN AL-MUSLIM · 268 DUAS"'
check "the first chapter is cursored ($(duas '.rows[0]'))" duas_is '.cursor == 0 and .rows[0].text == "When waking up" and .rows[0].current'
check "the pane says nothing is open yet ($(duas .pane.hint))" duas_is '.pane.hint == "Enter opens a chapter" and .pane.title == ""'
check "the keys read the board's seven ($(duas .keys))" duas_is '.keys == [["J/K","CHAPTER"],["↵","OPEN"],["N","NEXT DUA"],["Y","COPY"],["/","SEARCH"],["TAB","SECTION"],["ESC","CLOSE"]]'

wtype '/'
until_ok 2000 duas_is '.field.open'
wtype sleeping
until_ok 2000 duas_is '.rows | length == 1'
check "the field filters to the matching chapter ($(duas '.rows | map(.text)'))" duas_is '.field.text == "sleeping" and .rows[0].text == "Before sleeping"'
wtype -k Return
until_ok 2000 duas_is '.pane.title == "Before sleeping"'
check "Enter opens Before sleeping's first dua, closes the field and keeps the cursor on the chapter ($(duas '[.pane.title, .pane.head, .cursor, .field.open]'))" \
  duas_is '.pane.title == "Before sleeping" and .pane.head == "dua 1 of 13" and .cursor == 27 and (.field.open | not) and .field.text == ""'

wtype nnnnnn
until_ok 2000 duas_is '.pane.head == "dua 7 of 13"'
check "n steps six duas on to dua 105 ($(duas .pane.head))" duas_is '.pane.head == "dua 7 of 13"'
check "its Arabic, tatweel and harakat stripped, is the plan's letters" test "$(deen_state | jq -r .duas.pane.ar | letters)" = "باسمك اللهم اموت واحيا"
check "its Arabic keeps the book's tatweel" duas_is '.pane.ar | contains("ـ")'
check "its Arabic draws right to left in the Arabic face ($(duas '[.pane.arFamily, .pane.arRtl, .pane.arSize]'))" \
  deen_is '.duas.pane.arRtl and .duas.pane.arFamily == .arabic'
check "its transliteration starts as the board's" duas_is '.pane.tr | startswith("Bismika Allāhumma amūtu wa aḥyā")'
check "its meaning starts as the book's" duas_is '.pane.en | startswith("In Your Name, O Allah, I die and I live")'
check "its source draws the ref wrapped, then the book and its id ($(duas '.pane.sourceLines'))" \
  duas_is '.pane.source | startswith("Here, dying and living") and endswith(" · Hisn al-Muslim 105")'
check "the pane's labels read as Paper's caps ($(duas '[.pane.trLabel, .pane.enLabel, .pane.sourceLabel]'))" \
  duas_is '[.pane.trLabel, .pane.enLabel, .pane.sourceLabel] == ["TRANSLITERATION","MEANING","SOURCE"]'
check "the source wraps onto more than one line" duas_is '.pane.sourceLines > 1'

wtype y
want=$(deen_state | jq -r '.duas.pane | [.ar, .tr, .en, .source] | join("\n")')
copied() { [ "$(wl-paste --no-newline 2>/dev/null)" = "$want" ]; }
until_ok 3000 copied
check "y puts the four lines on the clipboard" copied
check "the key strip says it was copied" duas_is '.keys[3] == ["Y","COPIED"]'

wtype nnnnnnn
until_ok 2000 duas_is '.pane.head == "dua 1 of 13"'
check "n past the chapter's last dua wraps to its first ($(duas .pane.head))" duas_is '.pane.head == "dua 1 of 13" and .keys[3] == ["Y","COPY"]'

wtype -k Escape
until_ok 3000 deen_gone
until_ok 3000 no_deen_process
check "Esc on the page, the field closed, closes the window" deen_gone
check "and no deen qs is left" no_deen_process

open_deen
until_ok 5000 deen_up
wtype -k Shift_L
wtype -k Tab -k Tab
until_ok 5000 duas_is '.rows | length > 0'
# 40 j's from the top pass the first screen of rows, and the cursored row must stay inside the list.
wtype "$(many j 40)"
until_ok 3000 duas_is '.cursor == 40'
check "40 j's move the cursor to the 41st chapter and the list scrolls to keep it in view ($(duas '[.cursor, (.rows[] | select(.current))]'))" \
  duas_is '.cursor == 40 and ([.rows[] | select(.current and .inView)] | length) == 1 and ([.rows[] | select(.text == "When waking up" and .inView)] | length) == 0'
wtype "$(many k 40)"
until_ok 3000 duas_is '.cursor == 0'
check "40 k's scroll it back ($(duas '[.cursor, (.rows[0])]'))" duas_is '.cursor == 0 and .rows[0].text == "When waking up" and .rows[0].inView'

wtype '/forged'
until_ok 2000 duas_is '.rows | length == 1'
check "the forged chapter draws on one line without its controls ($(duas '.rows[0].text'))" \
  duas_is '.rows[0].text == "Forged chapter [31m" and .rows[0].lines == 1 and (.rows[0].text | test("[\u0000-\u001f‪-‮]") | not)'
wtype -k Escape
until_ok 2000 duas_is '(.field.open | not) and .field.text == "" and (.rows | length) > 1'
check "Esc in the field closes only the field, the window stays ($(deen_windows))" test "$(deen_windows)" = 1
check "and the whole list is back" duas_is '.cursor == 0 and .rows[0].text == "When waking up"'
wtype '/long chapter'
until_ok 2000 duas_is '.rows | length == 1'
check "the 200-character chapter is elided on one line ($(duas '.rows[0] | [.lines, .truncated]'))" duas_is '.rows[0].truncated and .rows[0].lines == 1 and (.rows[0].text | startswith("Long chapter name"))'
wtype -k Escape
until_ok 2000 duas_is '.field.open | not'

# Each theme's board detail, with Before sleeping's dua 7 open.
wtype '/sleeping'
until_ok 2000 duas_is '.rows | length == 1'
wtype -k Return nnnnnn
until_ok 2000 duas_is '.pane.head == "dua 7 of 13"'
check "paper: ruled box, solid divider, ink cursor row, serif title ($(duas .look))" \
  duas_is '.look.fieldRadius == 0 and .look.fieldBorder == 1 and .look.fieldFill == "" and (.look.dividerDashed | not) and .look.titleSize == 25 and .look.titleFont != .look.headFont and .look.italic'
check "paper: the cursor row is a square ink block ($(duas '.rows[] | select(.current)'))" duas_is '.rows[] | select(.current) | .radius == 0 and .fill == "#1c1915"'

in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: the heading, the labels and the dua's head read in sentence case ($(duas '[.heading, .pane.trLabel, .pane.head]'))" \
  duas_is '.heading == "Hisn al-Muslim · 268 duas" and .pane.trLabel == "Transliteration" and .pane.enLabel == "Meaning" and .pane.sourceLabel == "Source" and .pane.head == "dua 7 of 13"'
check "artboard: the keys are plain ($(duas .keys))" duas_is '.keys[0] == ["j/k","chapter"] and .keys[3] == ["y","copy"]'
check "artboard: a filled pill field, a 20 px bold title ($(duas .look))" duas_is '.look.fieldRadius == 12 and .look.fieldFill == "#f6f7f9" and .look.fieldBorder == 0 and .look.titleSize == 20'
check "artboard: the cursor row is a tinted rounded pill ($(duas '.rows[] | select(.current)'))" duas_is '.rows[] | select(.current) | .radius == 10 and .fill == "#eef1ff"'

in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: the heading, the labels and the dua's head read in capitals ($(duas '[.heading, .pane.trLabel, .pane.head]'))" \
  duas_is '.heading == "HISN AL-MUSLIM · 268 DUAS" and .pane.trLabel == "TRANSLITERATION" and .pane.head == "DUA 7 OF 13"'
check "blueprint: the keys are bracketed ($(duas .keys))" duas_is '.keys == [["[J/K]","CHAPTER"],["[↵]","OPEN"],["[N]","NEXT DUA"],["[Y]","COPY"],["[/]","SEARCH"],["[TAB]","SECTION"],["[ESC]","CLOSE"]]'
check "blueprint: a dashed divider, an 18 px title ($(duas .look))" duas_is '.look.dividerDashed and .look.titleSize == 18 and .look.fieldRadius == 0 and .look.fieldBorder == 1'
check "blueprint: the cursor row is an accent block ($(duas '.rows[] | select(.current)'))" duas_is '.rows[] | select(.current) | .radius == 0 and .fill == "#7fe3f0"'

wtype -k Escape
until_ok 3000 deen_gone
until_ok 3000 no_deen_process
check "Esc closes the window" deen_gone
check "and within 3 s no qs with -p .../shell/deen.qml is left" no_deen_process

# A backend with no book answers an error, and the page says so rather than drawing nothing.
cat >"$work/no-book" <<'SCRIPT'
#!/bin/sh
echo '{"error":"no duas.json"}'
exit 1
SCRIPT
chmod +x "$work/no-book"
open_deen "$work/no-book"
until_ok 5000 deen_up
wtype -k Shift_L
wtype -k Tab -k Tab
until_ok 5000 duas_is '.failed != ""'
check "a failed list draws that the book is not here yet ($(duas .failed))" duas_is '.failed == "Hisn al-Muslim is not on this machine yet" and .rows == [] and .pane.shown == false'
wtype -k Escape
until_ok 3000 deen_gone
until_ok 3000 no_deen_process
check "Esc closes the window and no deen qs is left" no_deen_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
