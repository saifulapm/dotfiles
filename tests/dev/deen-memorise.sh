#!/usr/bin/env bash
# Deen's Memorise: today's due cards one at a time, the first words until space reveals the rest, then 1 to 4 rates the card and the count drops; s skips, Tab and Esc reach the frame.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log
calls=$DOTS_DEV_DIR/deen.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
mem_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
mem() { deen_state | jq -c ".memorise | $1"; }
fixture=$repo/dev/deen/hifz-due---limit-40.json
# The cue and the whole ayah as the fixture holds them, so the check does not retype Arabic.
cue12=$(jq -r '.due[0].ayah.ar | split(" ") | .[0:2] | join(" ")' "$fixture")
full12=$(jq -r '.due[0].ayah.ar' "$fixture")
cue13=$(jq -r '.due[1].ayah.ar | split(" ") | .[0]' "$fixture")
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
logged() { grep -qxF -- "$1" "$calls"; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_deen() { niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"; }

in_theme paper
open_deen
until_ok 5000 deen_up
check "Deen opens ($(deen_windows) window)" deen_up

# The deck and the surah names are asked for when the App opens, so the page is ready; Read asks for the names too.
check "the deck is asked for once with a limit of 40, and the surah names" \
  bash -c "grep -cxF 'hifz due --limit 40' '$calls' | grep -qx 1 && grep -qxF 'api surahs' '$calls'"

wtype -k Shift_L
wtype -k Tab
until_ok 2000 deen_is '.tab == "memorise"'
until_ok 3000 mem_is '.memorise.status == "card"'
check "Tab reaches Memorise ($(deen_state | jq -c '[.tab, .heading]'))" deen_is '.tab == "memorise" and .heading == "Memorise"'
check "the top reads 7 due today and 2 new, 1 of 7 ($(mem '[.count, .line]'))" \
  mem_is '.memorise.count == "7 due today" and .memorise.line == "2 new · 1 of 7 · self-graded, nothing is recorded"'
check "the card shows only the first half of 1:2's words with two blanks and the recite line ($(mem '.card | [.arabic, .blanks, .recite, .hint]'))" \
  mem_is --arg cue "$cue12" '.memorise.card | .arabic == $cue and .blanks == 2 and .recite == "Recite the rest aloud. No microphone: you judge yourself." and .hint == "space reveal the rest" and .meaning == "" and .ratings == []'
check "the heading names the surah from api surahs ($(mem .card.heading))" mem_is '.memorise.card.heading == "Al-Faatiha · ayah 2" and .memorise.card.badge == "1 · RECALL"'
check "the card draws in Amiri or Noto Naskh Arabic ($(mem .card.arabicFont))" mem_is '.memorise.card.arabicFont == .arabic'

wtype 3
sleep 0.5
check "3 before space does nothing ($(mem '[.revealed, .count]'))" mem_is '.memorise.revealed == false and .memorise.count == "7 due today"'
check "and no grade was asked for" bash -c "! grep -q '^hifz grade' '$calls'"

wtype -k space
until_ok 2000 mem_is '.memorise.revealed == true'
check "space reveals the whole ayah and its meaning ($(mem '.card | [.arabic, .meaning]'))" \
  mem_is --arg full "$full12" '.memorise.card | .arabic == $full and .meaning == "[All] praise is [due] to Allah, Lord of the worlds -" and .badge == "2 · REVEALED" and .blanks == 0'
check "the four ratings read the card's next ($(mem '.card.ratings | map([.key, .word, .next])'))" \
  mem_is '.memorise.card.ratings | map([.key, .word, .next]) == [["1","again","10 min"],["2","hard","1 day"],["3","good","1 day"],["4","easy","1 day"]]'
check "Paper heads the ratings in capitals ($(mem .card.ask))" mem_is '.memorise.card.ask == "HOW DID IT GO · NEXT REVIEW"'

wtype 3
until_ok 2000 mem_is '.memorise.count == "6 due today"'
check "3 logs hifz grade 1:2 good" logged 'hifz grade 1:2 good'
check "the count reads 6 and 1:3 shows unrevealed ($(mem '[.count, .line, .card.heading, .card.arabic, .revealed]'))" \
  mem_is --arg cue "$cue13" '.memorise | .count == "6 due today" and .line == "1 new · 1 of 6 · self-graded, nothing is recorded" and .card.heading == "Al-Faatiha · ayah 3" and .card.arabic == $cue and .revealed == false and .card.meaning == ""'

wtype -k space
until_ok 2000 mem_is '.memorise.revealed == true'
wtype 1
until_ok 2000 mem_is '.memorise.count == "5 due today"'
check "space then 1 logs hifz grade 1:3 again" logged 'hifz grade 1:3 again'
check "the count reads 5 and 1:4 shows ($(mem '[.count, .line, .card.heading]'))" \
  mem_is '.memorise | .count == "5 due today" and .line == "0 new · 1 of 5 · self-graded, nothing is recorded" and .card.heading == "Al-Faatiha · ayah 4"'

wtype s
until_ok 2000 mem_is '.memorise.card.heading == "Al-Faatiha · ayah 5"'
check "s moves to the next card with the count unchanged ($(mem '[.count, .card.heading]'))" mem_is '.memorise.count == "5 due today" and .memorise.card.heading == "Al-Faatiha · ayah 5"'
check "and rated nothing" bash -c "! grep -q 'hifz grade 1:4' '$calls'"

wtype -k space
until_ok 2000 mem_is '.memorise.revealed == true'
check "a meaning with a newline, an override and an escape draws on one clean line ($(mem .card.meaning))" \
  mem_is '.memorise.card.meaning == "Master of the Day of Judgment, the real [31m end" and .memorise.card.meaningLines == 1'
wtype s
until_ok 2000 mem_is '.memorise.card.heading == "Al-Faatiha · ayah 6"'
wtype -k space
until_ok 2000 mem_is '.memorise.revealed == true'
check "a 200 character meaning wraps and is not cut ($(mem '.card | [.meaningLines, .meaningTruncated]'))" \
  mem_is '(.memorise.card.meaning | length) == 200 and .memorise.card.meaningLines > 1 and .memorise.card.meaningTruncated == false'

check "paper: a square card with a 2px ink border and square rating tiles ($(mem '.card | [.radius, .border, .fill]'))" \
  mem_is '.memorise.card | .radius == 0 and .border == 2 and .fill == "#00000000" and (.ratings | all(.radius == 0))'

in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: a rounded white card with an accent outline, tinted badge and rounded tiles ($(mem '.card | [.radius, .border, .fill, .borderColor, .badgeFill, .badge, .ask]'))" \
  mem_is '.memorise.card | .radius == 14 and .border == 1.5 and .fill == "#ffffff" and .borderColor == "#3d5afe" and .badgeFill == "#eef1ff" and .badge == "2 · revealed" and .ask == "How did it go · next review" and (.ratings | all(.radius == 12))'
check "artboard: the count reads in sentence case ($(mem '[.count, .line]'))" mem_is '.memorise.count == "5 due today"'

in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: a square 1px card in the accent, bracketed badge, capitals and the mono face ($(mem '.card | [.radius, .border, .borderColor, .badge, .ask, .askFont]'))" \
  mem_is '.memorise.card | .radius == 0 and .border == 1 and .borderColor == "#7fe3f0" and .badge == "[2 · REVEALED]" and .ask == "HOW DID IT GO · NEXT REVIEW" and .askFont == "Maple Mono"'
check "blueprint: the count and the ratings read in capitals and the key strip in brackets ($(mem '[.count, .card.ratings[0].next, .keys[0]]'))" \
  mem_is '.memorise.count == "5 DUE TODAY" and .memorise.card.ratings[0].next == "10 MIN" and .memorise.keys[0] == ["[SPACE]","REVEAL"] and .memorise.keys[7] == ["[ESC]","CLOSE"]'

in_theme paper
until_ok 3000 deen_is '.voice == "caps"'
check "paper: the key strip reads SPACE REVEAL to ESC CLOSE ($(mem .keys))" mem_is '.memorise.keys[0] == ["SPACE","REVEAL"] and (.memorise.keys | length) == 8'

wtype -k Escape
until_ok 3000 deen_gone
check "Esc closes the window" deen_gone
until_ok 3000 no_deen_process
check "and within 3 s no qs with -p .../shell/deen.qml is left" no_deen_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
