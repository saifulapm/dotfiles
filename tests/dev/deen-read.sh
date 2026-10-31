#!/usr/bin/env bash
# Deen's Read draws a surah word by word right to left with each word's and each ayah's Bangla meaning, boxes the cursor's word with its meaning, transliteration and root in the bar, plays a word or the surah through mpv, and opens another surah from the picker.
{
source "$(dirname "$0")/lib.sh"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
log=$work/deen.log
mpv_log=$work/mpv.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
read_is() { deen_state | jq -e ".read | $1" >/dev/null 2>&1; }
read_show() { deen_state | jq -c ".read | $1"; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
deen_pids() { session_qs_pids "-p $deen_qml"; }
no_deen_process() { [ -z "$(deen_pids)" ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
mpv_lines() { [ -f "$mpv_log" ] && wc -l <"$mpv_log" || echo 0; }
mpv_at_least() { [ "$(mpv_lines)" -ge "$1" ]; }
mpv_line() { sed -n "${1}p" "$mpv_log" 2>/dev/null; }
mpv_pid() { mpv_line "$1" | cut -d' ' -f1; }
mpv_args() { mpv_line "$1" | cut -d' ' -f2-; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
dead() { ! alive "$1"; }
no_player_left() {
  local pid
  for pid in $(cut -d' ' -f1 "$mpv_log"); do alive "$pid" && return 1; done
  return 0
}
fake_called() { grep -qx "$1" "$DOTS_DEV_DIR/deen.log"; }

# What Read says in place of its body when deen has no Bangla to draw.
no_data="Bangla data is not on this machine: gh auth login, then dots update"

# The player stub logs its pid and argv, then becomes a sleep, so it plays as long as mpv would and dies as one process.
stub=$work/mpv-stub
printf '#!/bin/sh\necho "$$ $*" >>%s\nexec sleep 300\n' "$mpv_log" >"$stub"
chmod +x "$stub"

exec_line=$(sed -n 's/^Exec=//p' "$entry")
# A backend script as $1 answers in place of the fake deen.
open_deen() { niri msg action spawn -- sh -c "${1:+DOTS_DEEN=$1 }DOTS_DEEN_MPV='$stub' exec $exec_line >>'$log' 2>&1"; }

in_theme paper
open_deen
until_ok 5000 deen_up
check "Deen opens on Read ($(deen_state | jq -c .tab))" deen_is '.tab == "read"'
until_ok 3000 read_is '.ayat == 7 and (.ayah.words | length) == 4'

check "Read opens on Al-Fatihah with its 7 ayat drawn ($(read_show '[.heading, .ayat]'))" read_is '.heading == "Surah 1 · Al-Faatiha" and .ayat == 7 and .failed == ""'
check "the heading names it in Arabic and reads its count, kind and juz ($(read_show '[.arabic, .meta]'))" \
  read_is '.arabic == "سُورَةُ ٱلْفَاتِحَةِ" and .meta == "7 ayat · Makki · juz 1"'
check "1:1's first word is بِسْمِ over its Bangla meaning নামে, boxed ($(read_show '.ayah.words[0] | [.ar, .bn, .boxed]'))" \
  read_is '.ayah.number == "1" and .ayah.words[0].ar == "بِسْمِ" and .ayah.words[0].bn == "নামে" and .ayah.words[0].boxed and ([.ayah.words[] | select(.boxed)] | length) == 1'
# Zakaria's 1:1, with the zero-width non-joiner after আল্লাহ্'s hasanta that keeps it from joining র.
bn11=$(printf 'রহমান, রহীম আল্লাহ্\u200cর নামে')
check "1:1's Bangla meaning draws under its words ($(read_show '.ayah | [.bn, .bnLines]'))" \
  deen_is --arg bn "$bn11" '.read.ayah.bn == $bn and .read.ayah.bnLines == 1'
check "paper: the ayah's, the word's and the bar's Bangla draw in Noto Serif Bengali ($(read_show '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily]'))" \
  read_is '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily] == ["Noto Serif Bengali", "Noto Serif Bengali", "Noto Serif Bengali"]'
check "Arabic reads right to left: word 1 is drawn right of word 2, and word 2 right of word 3 ($(read_show '[.ayah.words[] | .x]'))" \
  read_is '.ayah.words[0].x > .ayah.words[1].x and .ayah.words[1].x > .ayah.words[2].x'
check "the words draw in Amiri or Noto Naskh Arabic ($(read_show '.ayah.words[0].family'))" \
  read_is '.ayah.words[0].family == "Amiri" or .ayah.words[0].family == "Noto Naskh Arabic"'
check "the bar reads the boxed word's Bangla meaning, transliteration and root ($(read_show '.bar | [.word, .bn, .line, .hint]'))" \
  read_is '.bar.word == "بِسْمِ" and .bar.bn == "নামে" and .bar.line == "bis'"'"'mi · ayah 1, word 1 · root س م و" and .bar.hint == "↵ hear this word"'
check "the heading's hints and the key strip name Read's keys ($(read_show '[.hints, (.keys | map(.[0]))]'))" \
  read_is '.hints == ["S SURAH", "P PLAY SURAH"] and (.keys | map(.[0])) == ["H/L", "J/K", "↵", "P", "S", "/", "M", "TAB", "ESC"]'
check "paper: the box is a 2 px red rule on cream, the bar a 1 px ink rule, the heading in its display face ($(read_show '[.box, .bar.border, .bar.borderColor, .headingFont]'))" \
  read_is '.box.border == 2 and .box.borderColor == "#c8381e" and .box.fill == "#f3e6cf" and .box.radius == 0 and .bar.border == 1 and .bar.borderColor == "#1c1915" and .bar.fill == "" and .ayah.ruleDashed == false'

wtype -k Shift_L
wtype h
# Allah as the backend spells it, shadda before fatha.
word2=$(printf '\u0671\u0644\u0644\u0651\u064e\u0647\u0650')
until_ok 2000 read_is '.ayah.words[1].boxed'
check "h moves the box to word 2, ٱللَّهِ, left of word 1 ($(read_show '[.ayah.words[1] | .ar, .boxed, .x]'))" \
  deen_is --arg w "$word2" '.read | .ayah.words[1].boxed and .ayah.words[1].ar == $w and .ayah.words[1].x < .ayah.words[0].x and (.ayah.words[0].boxed | not) and .bar.line == "l-lahi · ayah 1, word 2 · root أ ل ه"'

wtype -k Return
until_ok 3000 mpv_at_least 1
check "Enter plays the word through the player with audio 1:1:2's path ($(mpv_args 1))" \
  test "$(mpv_args 1)" = "--no-video --really-quiet /nonexistent/001_001_002.mp3"
check "the player runs, a child of Deen's process ($(mpv_pid 1))" alive "$(mpv_pid 1)"

wtype p
until_ok 3000 mpv_at_least 2
queue=$(jq -r '.queue | join(" ")' "$repo/dev/deen/audio-1:1---to-end.json")
check "p plays the surah from the cursor's ayah as one player with 1:1's queue ($(mpv_args 2 | head -c 120))" \
  test "$(mpv_args 2)" = "--no-video --really-quiet $queue"
until_ok 2000 dead "$(mpv_pid 1)"
check "and p stopped the word that was playing" dead "$(mpv_pid 1)"
check "the page says the surah plays ($(read_show .playing))" read_is '.playing == "surah"'
wtype p
until_ok 2000 dead "$(mpv_pid 2)"
check "p while the surah plays stops it ($(read_show .playing))" dead "$(mpv_pid 2)"
until_ok 2000 read_is '.playing == ""'

# Ayah 7's last two meanings are forged: one holds a newline, U+202E and ESC, the other is 200 characters.
wtype jjjjjj
until_ok 2000 read_is '.ayah.number == "7"'
check "j six times reaches 1:7 with its first word boxed ($(read_show '[.ayah.number, .ayah.words[0].boxed]'))" read_is '.ayah.number == "7" and .ayah.words[0].boxed'
check "a meaning with a newline, U+202E and ESC draws as one plain line ($(read_show '.ayah.words[-1] | [.bn, .lines]'))" \
  read_is '.ayah.words[-1].bn == "জাল লাইন [31m শেষ" and .ayah.words[-1].lines == 1'
check "a 200-character meaning draws one line, elided ($(read_show '.ayah.words[-2] | [.lines, .truncated]'))" \
  read_is '.ayah.words[-2].lines == 1 and .ayah.words[-2].truncated'

wtype l
until_ok 2000 read_is '.ayah.number == "6"'
check "l before an ayah's first word goes to the previous ayah's last ($(read_show '[.ayah.number, .bar.line]'))" \
  read_is '.ayah.number == "6" and .ayah.words[-1].boxed and .bar.line == "l-mus'"'"'taqīma · ayah 6, word 3 · root ق و م"'

wtype s
until_ok 2000 read_is '.picker.open and .picker.focused'
check "s opens the surah picker with the field focused, listing all 114 ($(read_show '.picker | [.open, .count]'))" read_is '.picker.open and .picker.count == 114'
wtype 36
until_ok 2000 read_is '.picker.text == "36"'
check "typing 36 puts Yaseen first, cursored ($(read_show '.picker.rows'))" \
  read_is '.picker.rows[0].n == "36" and .picker.rows[0].name == "Yaseen" and .picker.rows[0].current and .picker.rows[0].fill == "#1c1915"'
wtype -k Return
until_ok 3000 read_is '.ayat == 83'
check "Enter opens Ya-Sin with its 83 ayat ($(read_show '[.heading, .ayat, .picker.open]'))" \
  read_is '.heading == "Surah 36 · Yaseen" and .ayat == 83 and (.picker.open | not)'
check "its heading reads 83 ayat · Makki · juz 22 ($(read_show .meta))" read_is '.meta == "83 ayat · Makki · juz 22"'
check "36:1's word has no root, so the bar names none ($(read_show .bar.line))" read_is '.bar.line == "ya-seen · ayah 1, word 1"'

wtype j
until_ok 2000 read_is '.ayah.number == "2"'
check "j moves to 36:2 ($(read_show '[.ayah.number, .bar.line]'))" read_is '.ayah.number == "2" and .ayah.words[0].boxed and .bar.line == "wal-qur'"'"'āni · ayah 2, word 1 · root ق ر أ"'

wtype m
until_ok 3000 fake_called "hifz add 36"
check "m asks the backend to add surah 36 to Memorise" fake_called "hifz add 36"
until_ok 2000 read_is '.bar.hint == "Yaseen added to Memorise"'
check "and the bar says so ($(read_show .bar.hint))" read_is '.bar.hint == "Yaseen added to Memorise"'

wtype /
until_ok 2000 read_is '.picker.open and .picker.focused'
check "/ opens the same picker ($(read_show '.picker.open'))" read_is '.picker.open'
wtype -k Escape
until_ok 2000 read_is '.picker.open | not'
check "Esc in the picker closes only the picker ($(deen_windows) window, picker $(read_show .picker.open))" deen_up
check "and leaves Ya-Sin open" read_is '.heading == "Surah 36 · Yaseen" and (.picker.open | not)'

wtype s
until_ok 2000 read_is '.picker.open and .picker.focused'
wtype 94
until_ok 2000 read_is '.picker.text == "94"'
wtype -k Return
until_ok 3000 read_is '.ayat == 8'
check "s, 94 and Enter open Ash-Sharh ($(read_show '[.heading, .ayat]'))" read_is '.heading == "Surah 94 · Ash-Sharh" and .ayat == 8'
wtype jjjjj
until_ok 2000 read_is '.ayah.number == "6"'
inna=$(printf '\u0625\u0650\u0646\u0651\u064e')
usr=$(printf '\u0671\u0644\u0652\u0639\u064f\u0633\u0652\u0631\u0650')
check "94:6 draws its Arabic words, then its Bangla meaning as a line of the row ($(read_show '.ayah | [[.words[].ar], .bn]'))" \
  deen_is --arg inna "$inna" --arg usr "$usr" '.read.ayah | .words[0].ar == $inna and .words[2].ar == $usr and (.words | length) == 4 and .bn == "নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।" and .inkTop >= .wordsBottom'
check "إِنَّ draws নিশ্চয়ই and ٱلْعُسْرِ draws কষ্টের under them ($(read_show '[.ayah.words[] | .bn]'))" \
  read_is '[.ayah.words[] | .bn] == ["নিশ্চয়ই", "সাথে", "কষ্টের", "স্বস্তি (আছে)"]'
check "the bar's meaning line shows the boxed إِنَّ's Bangla ($(read_show .bar.bn))" read_is '.ayah.words[0].boxed and .bar.bn == "নিশ্চয়ই"'
wtype hh
until_ok 2000 read_is '.ayah.words[2].boxed'
check "hh boxes ٱلْعُسْرِ and the bar shows কষ্টের ($(read_show '[.bar.word, .bar.bn, .bar.line]'))" \
  deen_is --arg usr "$usr" '.read.bar.word == $usr and .read.bar.bn == "কষ্টের" and .read.bar.line == "l-ʿus'"'"'ri · ayah 6, word 3 · root ع س ر"'
no_english() { ! deen_state | jq -c .read | grep -q Indeed; }
check "no drawn text in Read holds English: Indeed is nowhere in its state" no_english
check "and Read's chrome reads as before ($(read_show '[.bar.hint, .hints[0]]'))" read_is '.bar.hint == "↵ hear this word" and .hints[0] == "S SURAH"'

# 36:18 holds যন্ত্রণাদায়ক, whose stacked ন্ত্র is the tallest glyph Read draws; its meaning wraps.
wtype s
until_ok 2000 read_is '.picker.open and .picker.focused'
wtype 36
until_ok 2000 read_is '.picker.text == "36"'
wtype -k Return
until_ok 3000 read_is '.ayat == 83 and .ayah.number == "1"'
one_row=$(read_show .ayah.height)
wtype jjjjjjjjjjjjjjjjj
until_ok 2000 read_is '.ayah.number == "18"'
check "paper: 36:18's meaning holds ন্ত্র in Noto Serif Bengali and wraps uncut ($(read_show '.ayah | [.bnFamily, .bnLines, .bnTruncated]'))" \
  read_is '(.ayah.bn | test("ন্ত্র")) and .ayah.bnFamily == "Noto Serif Bengali" and .ayah.bnLines >= 2 and (.ayah.bnTruncated | not)'
check "its ink sits inside the row, below the words and above the rule ($(read_show '.ayah | [.wordsBottom, .inkTop, .inkBottom, .height]'))" \
  read_is '.ayah.inkTop >= .ayah.wordsBottom and .ayah.inkBottom <= .ayah.height - 1'
check "and the row grew with its lines, taller than 36:1's one-line row ($one_row, $(read_show .ayah.height))" \
  deen_is --argjson one "$one_row" '.read.ayah.height > $one'
wtype kkkkkkkkkkkkkkkk
until_ok 2000 read_is '.ayah.number == "2"'

in_theme artboard
until_ok 3000 deen_is '.voice == "plain"'
check "artboard: the box is a 1.5 px accent line on its tint at radius 10, its meaning in deep blue ($(read_show .box))" \
  read_is '.box.border == 1.5 and .box.borderColor == "#3d5afe" and .box.fill == "#eef1ff" and .box.radius == 10 and .box.bnColor == "#2638c9"'
check "artboard: the Bangla draws in Noto Sans Bengali ($(read_show '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily]'))" \
  read_is '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily] == ["Noto Sans Bengali", "Noto Sans Bengali", "Noto Sans Bengali"]'
check "artboard: the tab still reads Read and the bar's hint ↵ hear this word ($(deen_state | jq -c '[.tabs[0].text, .read.bar.hint]'))" \
  deen_is '.tabs[0].text == "Read" and .read.bar.hint == "↵ hear this word"'
check "artboard: the bar is filled grey at radius 12 with no rule, the keys in lower case ($(read_show '[.bar.fill, .bar.radius, .bar.border, .hints]'))" \
  read_is '.bar.fill == "#f6f7f9" and .bar.radius == 12 and .bar.border == 0 and .hints == ["s surah", "p play surah"]'

in_theme blueprint
until_ok 3000 deen_is '.voice == "bracket"'
check "blueprint: the ayat are ruled dashed and the heading line and bar read in capitals ($(read_show '[.ayah.ruleDashed, .meta, .bar.line, .bar.hint]'))" \
  read_is '.ayah.ruleDashed and .ayah.ruleColor == "#2e5a72" and .meta == "83 AYAT · MAKKI · JUZ 22" and .bar.line == "WAL-QUR'"'"'ĀNI · AYAH 2, WORD 1 · ROOT ق ر أ"'
check "blueprint: the Bangla draws in Noto Sans Bengali ($(read_show '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily]'))" \
  read_is '[.ayah.bnFamily, .ayah.words[0].bnFamily, .bar.bnFamily] == ["Noto Sans Bengali", "Noto Sans Bengali", "Noto Sans Bengali"]'
check "blueprint: the box and the bar are 1 px accent lines on no fill, the keys bracketed ($(read_show '[.box, .bar.borderColor, .hints]'))" \
  read_is '.box.border == 1 and .box.borderColor == "#7fe3f0" and .box.fill == "" and .bar.border == 1 and .bar.borderColor == "#7fe3f0" and .hints == ["[S] SURAH", "[P] PLAY SURAH"]'

wtype k
until_ok 2000 read_is '.ayah.number == "1"'
wtype -k Return
until_ok 3000 mpv_at_least 3
check "k back to 36:1 and Enter play its first word ($(mpv_args 3))" test "$(mpv_args 3)" = "--no-video --really-quiet /nonexistent/036_001_001.mp3"
check "and the player runs as Esc comes" alive "$(mpv_pid 3)"
wtype -k Escape
until_ok 3000 deen_gone
check "Esc on the page closes the window" deen_gone
until_ok 3000 no_deen_process
check "and within 3 s no qs with -p .../shell/deen.qml is left" no_deen_process
until_ok 3000 no_player_left
check "and no player it started is left" no_player_left

# A machine without the Quran text: deen answers each call with its no-data error.
cat >"$work/no-quran" <<'SCRIPT'
#!/bin/sh
echo '{"error":"cannot read the Quran text at /nonexistent/quran.json: No such file or directory (os error 2)"}'
exit 1
SCRIPT
# Data older than the words' Bangla meanings: the fake deen's surahs with every word's bn taken out.
cat >"$work/no-word-bn" <<SCRIPT
#!/bin/sh
[ "\$1 \$2" = "api surah" ] || exec "$repo/bin/dev-fake-deen" "\$@"
"$repo/bin/dev-fake-deen" "\$@" | jq -c 'del(.words[][].bn)'
SCRIPT
chmod +x "$work/no-quran" "$work/no-word-bn"
for backend in no-quran no-word-bn; do
  in_theme paper
  open_deen "$work/$backend"
  until_ok 5000 deen_up
  wtype -k Shift_L
  until_ok 3000 read_is '.failed != ""'
  check "$backend: Read says how to get the Bangla in place of its body ($(read_show '[.failed, .heading, .ayah]'))" \
    deen_is --arg m "$no_data" '.read.failed == $m and .read.ayah == null'
  wtype -k Escape
  until_ok 3000 deen_gone
  until_ok 3000 no_deen_process
  check "$backend: Esc closes the window and no deen qs is left" no_deen_process
done

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
