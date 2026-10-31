#!/usr/bin/env bash
# Deen's Show path on the real deen backend and the data it builds from the deen-data checkout, pointed at the backend's fake editions CDN and fake aladhan: Read surah 36 and hear its first word in mpv, add it to Memorise, reveal an ayah and press 3 so it leaves today's list, see the next prayer's countdown, and get the hadith corpus through a cut and a resume.
{
source "$(dirname "$0")/lib.sh"

backend=/home/saiful/Codes/deen
deen_bin=$backend/target/debug/deen
editions_bin=$backend/target/debug/examples/fake_editions
aladhan_bin=$backend/target/debug/examples/fake_aladhan
sources=/home/saiful/Codes/deen-data
deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
log=$work/deen.log
editions_pid='' aladhan_pid=''
stop() { [ -z "$1" ] || { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }; }
cleanup() {
  stop "$editions_pid"
  stop "$aladhan_pid"
  rm -rf "$work"
}

if ! cargo build --offline -q --manifest-path "$backend/Cargo.toml" --bin deen --example fake_editions --example fake_aladhan; then
  echo "FAIL the backend at $backend builds"
  exit 1
fi
mkdir -p "$work"/{config,cache/deen/audio/wbw,state,data,hadith,editions,mpv}
# The Quran text, its word meanings and Hisn al-Muslim, built by the backend from the deen-data checkout as the pin's apply builds them.
texts=$work/texts
if ! DEEN_BIN=$deen_bin "$backend/scripts/build-data" "$sources" "$texts"; then
  echo "FAIL the backend builds its data from $sources"
  exit 1
fi
ln -s "$DOTS_DEV_DIR/state/dots" "$work/state/dots"
printf 'ao=null\n' >"$work/mpv/mpv.conf"
# 36:1's first word, recorded as the CDN's file would be, so Enter plays it without the network.
ffmpeg -hide_banner -loglevel error -y -f lavfi -i sine=frequency=440:duration=30 "$work/cache/deen/audio/wbw/036_001_001.mp3"

# Ten collections' editions as the CDN serves them: Bukhari 1 holds the intentions hadith, padded so the cut lands inside it.
python3 -I - "$work/editions" <<'PY'
import json, sys
out = sys.argv[1]
for c in "bukhari muslim abudawud tirmidhi nasai ibnmajah malik nawawi qudsi dehlawi".split():
    ar = "إنما الأعمال بالنيات " * 4000 if c == "bukhari" else f"حديث {c}"
    en = ("Narrated 'Umar bin Al-Khattab: I heard Allah's Messenger saying, \"The reward of deeds depends upon the intentions.\""
          if c == "bukhari" else f"Narrated someone: a saying from {c}.")
    langs = [("ara", ar), ("eng", en)] + ([] if c in ("qudsi", "dehlawi") else [("ben", "কাজের ফল নিয়তের উপর নির্ভরশীল")])
    for lang, text in langs:
        edition = {"metadata": {"name": f"Collection {c}", "sections": {"1": "Revelation"}},
                   "hadiths": [{"hadithnumber": 1, "text": text, "grades": [], "reference": {"book": 1, "hadith": 1}}]}
        json.dump(edition, open(f"{out}/{lang}-{c}.min.json", "w"), ensure_ascii=False)
PY
total=$(cat "$work"/editions/*.json | wc -c)

# start_editions [cut bytes]: the fake CDN, cut after that many bytes when given, on the first one's port when there was one; slow enough that the download is seen running.
start_editions() {
  env FAKE_LOG="$work/editions.log" FAKE_SLOW_MS=2 FAKE_PORT=${editions_url##*:} ${1:+FAKE_CUT=$1} "$editions_bin" "$work/editions" >"$work/editions.addr" 2>"$work/editions.err" &
  editions_pid=$!
  until_ok 10000 test -s "$work/editions.addr" || { echo "FAIL the fake CDN started: $(cat "$work/editions.err")"; exit 1; }
  editions_url=http://$(head -1 "$work/editions.addr")
}
"$aladhan_bin" "$backend/tests/fixtures/aladhan-2026-10.json" "$work/aladhan.log" >"$work/aladhan.addr" 2>"$work/aladhan.err" &
aladhan_pid=$!
until_ok 10000 test -s "$work/aladhan.addr"
aladhan_url=http://127.0.0.1:$(head -1 "$work/aladhan.addr" | grep -oE '[0-9]+$')
editions_url=:0
start_editions $((total * 3 / 10))

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
show() { deen_state | jq -c "$1"; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_gone() { [ "$(deen_windows)" = 0 ]; }
deen_pids() { session_qs_pids "-p $deen_qml"; }
no_deen_process() { [ -z "$(deen_pids)" ]; }
# Whatever this run's Deen started (mpv, deen, its curl and python3) names the run's work dir in its command line or environment.
left_over() {
  local pid
  for pid in $(pgrep -x 'mpv|deen|curl|python3'); do
    cat "/proc/$pid/cmdline" "/proc/$pid/environ" 2>/dev/null | tr '\0' '\n' | grep -qF -- "$work" && echo "$pid"
  done
  return 0
}
nothing_left() { [ -z "$(deen_pids)" ] && [ -z "$(left_over)" ]; }
# The App's mpv, a child of its qs, found by its own cmdline.
mpv_playing() {
  local qs pid
  for qs in $(deen_pids); do
    for pid in $(pgrep -P "$qs" -x mpv); do
      tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" | grep -qF -- "$1" && return 0
    done
  done
  return 1
}
tab_to() { until deen_is --arg t "$1" '.tab == $t'; do wtype -k Tab; sleep 0.2; done; }

env_line="DOTS_DEEN=$deen_bin DEEN_DATA=$texts/quran.json DEEN_WORDS=$texts/words.json DEEN_DUAS=$texts/duas.json DEEN_HADITH=$work/hadith DEEN_STATE=$work/data/hifz.json DEEN_HADITH_URL=$editions_url DEEN_ALADHAN_URL=$aladhan_url DEEN_CONFIG=$work/config/none.toml DOTS_DEEN_NOW=2026-10-23T14:32 XDG_CONFIG_HOME=$work/config XDG_CACHE_HOME=$work/cache XDG_STATE_HOME=$work/state MPV_HOME=$work/mpv"
exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_deen() { niri msg action spawn -- sh -c "exec env $env_line $exec_line >>'$log' 2>&1"; }

open_deen
until_ok 5000 deen_up
check "Deen opens on the real backend in under 500 ms ($(show .firstFrameMs) ms)" deen_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
wtype -k Shift_L

# Read: s, 36, Enter opens Ya-Sin; Enter on its first word plays it.
until_ok 5000 deen_is '.read.ayat == 7'
wtype s
until_ok 2000 deen_is '.read.picker.open'
wtype 36
until_ok 2000 deen_is '.read.picker.text == "36"'
wtype -k Return
until_ok 5000 deen_is '.read.ayat == 83'
check "s, 36, Enter opens Ya-Sin with its 83 ayat ($(show '[.read.heading, .read.meta, .read.ayat]'))" deen_is '.read.ayat == 83 and (.read.meta | startswith("83 ayat · Makki · juz 22"))'
check "its first word shows with its Bangla meaning, from the built words.json ($(show '.read.ayah.words[0] | [.ar, .bn, .boxed]'))" \
  deen_is '.read.ayah.words[0].ar == "يسٓ" and .read.ayah.words[0].bn == "ইয়া-সীন।" and .read.ayah.words[0].boxed'
check "and its Arabic draws in an Arabic face ($(show '.read.ayah.words[0].family'))" deen_is '.read.ayah.words[0].family == "Amiri" or .read.ayah.words[0].family == "Noto Naskh Arabic"'
wtype -k Return
until_ok 5000 mpv_playing 036_001_001.mp3
check "Enter on it plays its recording in mpv" mpv_playing 036_001_001.mp3

# m adds the surah to Memorise; there a card shows its first words, space reveals it, and 3 takes it off today's list.
wtype m
until_ok 5000 test -s "$work/data/hifz.json"
check "m adds Ya-Sin's 83 ayat to the deck ($(jq '.cards | length' "$work/data/hifz.json" 2>/dev/null))" bash -c "[ \"\$(jq '.cards | length' '$work/data/hifz.json')\" = 83 ]"
tab_to memorise
until_ok 5000 deen_is '.memorise.count == "40 due today" or .memorise.count == "83 due today"'
check "Memorise counts today's cards ($(show '[.memorise.count, .memorise.line]'))" deen_is '.memorise.count == "83 due today" and (.memorise.line | startswith("83 new · 1 of 83"))'
check "the card shows only the start of 36:1 ($(show '[.memorise.card.heading, .memorise.card.arabic, .memorise.revealed]'))" \
  deen_is '.memorise.revealed == false and (.memorise.card.heading | test("ayah 1$")) and .memorise.card.meaning == ""'
wtype ' '
until_ok 2000 deen_is '.memorise.revealed'
check "space reveals the ayah and its meaning ($(show '[.memorise.card.arabic, .memorise.card.meaning]'))" deen_is '.memorise.revealed and .memorise.card.meaning != ""'
wtype 3
until_ok 5000 deen_is '.memorise.count == "82 due today"'
check "3 takes it off today's list: the count reads one less ($(show .memorise.count))" deen_is '.memorise.count == "82 due today" and .memorise.revealed == false'
first_due=$(jq '.cards["36:1"].due' "$work/data/hifz.json")
now_s=$(date +%s)
check "and the deck brings 36:1 back in a day, by SM-2 ($((first_due - now_s)) s)" test $((first_due - now_s)) -ge 86000 -a $((first_due - now_s)) -le 86400

# Prayer: Dhaka's day from the fake aladhan, with Hanafi Asr next at 14:32.
tab_to prayer
until_ok 5000 deen_is '(.prayer.rows | length) == 5'
check "Prayer draws Dhaka's five times for 2026-10-23 ($(show '[.prayer.rows[] | .time]'))" deen_is '[.prayer.rows[] | .time] == ["04:43","11:43","15:50","17:26","18:42"]'
check "the next prayer is Asr with its countdown ($(show '[.prayer.headline, .prayer.at]'))" deen_is '.prayer.headline == "Asr in 1 h 18 min" and .prayer.at == "15:50 · now 14:32"'
check "the backend asked aladhan for the Hanafi school" grep -q 'school=1' "$work/aladhan.log"

# Hadith: the download started when Deen opened, the fake CDN cut it, and r resumes it once the CDN is back.
tab_to hadith
until_ok 30000 deen_is '.hadith.download.fail != ""'
check "the cut download keeps what it saved ($(show '[.hadith.download.title, .hadith.download.kept]'))" deen_is '.hadith.download.fail != "" and .hadith.download.kept != ""'
kept=$(find "$work/hadith" -type f -name '*.part' -o -type f -name '*.min.json' | xargs -r cat | wc -c)
check "the saved part is on disk ($kept bytes of $total)" test "$kept" -gt 0 -a "$kept" -lt "$total"
stop "$editions_pid"
rm -f "$work/editions.addr"
start_editions
wtype r
until_ok 30000 deen_is '.hadith.ready'
check "r resumes it and the corpus is ready ($(show .hadith.search.foot))" deen_is '.hadith.ready and .hadith.search.shown'
check "from the saved part, by a Range request ($(grep -m1 'GET /ara-bukhari.min.json bytes=' "$work/editions.log"))" grep -q 'GET /ara-bukhari.min.json bytes=[1-9]' "$work/editions.log"
wtype intentions
until_ok 5000 deen_is '(.hadith.search.rows | length) > 0'
check "searching intentions finds Sahih al-Bukhari 1, offline on the saved corpus ($(show '.hadith.search.rows[0]'))" \
  deen_is '(.hadith.search.rows[0] | tostring | test("Sahih al-Bukhari")) and (.hadith.search.rows[0] | tostring | test("#1"))'

wtype -k Escape
until_ok 3000 deen_gone
check "Esc closes the window" deen_gone
until_ok 3000 nothing_left
check "and no deen qs, mpv, deen, curl or python3 of this run is left ($(left_over | tr '\n' ' '))" nothing_left

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
