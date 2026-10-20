#!/usr/bin/env bash
# Mod+Shift+R picks a region by keys, Enter records it with wf-recorder, and Mod+Shift+R again saves the file.
{
source "$(dirname "$0")/lib.sh"

rec_state() { timeout 0.5 qs ipc call record state 2>/dev/null; }
state_is() { rec_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_shift_r() { niri msg action spawn -- qs ipc call record toggle; }
# Only this session's recorder writes into its own recordings dir.
recorder_running() { pgrep -f "[w]f-recorder.*$DOTS_RECORDINGS_DIR" >/dev/null; }
island_text() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .text; }
island_recs() { [[ $(island_text) =~ ^REC\ 00:0[0-9]$ ]]; }
files() { find "$DOTS_RECORDINGS_DIR" -name '*.mp4' 2>/dev/null | wc -l; }

until_ok 5000 shell_status >/dev/null

# The picker's key hint reads in each theme's voice: Artboard plain, Blueprint bracketed, Paper caps.
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
for t in "artboard|hjkl move  ⇧HJKL size  f full  ↵ rec  esc cancel" \
  "blueprint|[HJKL] MOVE  [⇧HJKL] SIZE  [F] FULL  [↵] REC  [ESC] CANCEL" \
  "paper|HJKL MOVE  ⇧HJKL SIZE  F FULL  ↵ REC  ESC CANCEL"; do
  in_theme "${t%%|*}"
  mod_shift_r
  until_ok 3000 state_is '.picking'
  check "${t%%|*}: the hint reads ${t#*|} ($(rec_state | jq -c .hint))" state_is ".hint == \"${t#*|}\""
  wtype -k Escape
  until_ok 2000 state_is '.picking | not'
done

mod_shift_r
until_ok 3000 state_is '.picking'
check "Mod+Shift+R opens the picker" state_is '.picking and (.recording | not)'
x0=$(rec_state | jq .region.x)
step=$(rec_state | jq .step)
for _ in 1 2 3 4 5 6 7 8 9 10; do wtype l; done
moved() { state_is ".region.x == $x0 + 10 * $step"; }
until_ok 2000 moved
check "l ten times moves the region ten steps right ($x0 + 10 x $step)" moved

wtype -k Escape
until_ok 2000 state_is '.picking | not'
check "Esc closes the picker" state_is '(.picking | not) and (.recording | not)'
sleep 0.5
check "Esc starts no wf-recorder" bash -c "! pgrep -f '[w]f-recorder.*$DOTS_RECORDINGS_DIR' >/dev/null"

mod_shift_r
until_ok 3000 state_is '.picking'
wtype f
until_ok 2000 state_is '.region.x == 0 and .region.y == 0'
wtype -k Return
until_ok 3000 state_is '.recording'
check "Enter starts recording" state_is '.recording and (.picking | not)'
check "wf-recorder runs" recorder_running
until_ok 2000 island_recs
check "the island reads REC 00:0x" island_recs
echo "     island: $(island_text)"
sleep 3
mod_shift_r
until_ok 5000 state_is '.recording | not'
until_ok 3000 bash -c '! pgrep -f "[w]f-recorder.*'"$DOTS_RECORDINGS_DIR"'" >/dev/null'
check "Mod+Shift+R again stops wf-recorder" bash -c "! pgrep -f '[w]f-recorder.*$DOTS_RECORDINGS_DIR' >/dev/null"
check "one recording is saved" test "$(files)" = 1
f=$(find "$DOTS_RECORDINGS_DIR" -name '*.mp4' | head -1)
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
echo "     $f: ${dur:-no duration} s"
check "its duration is 3 +- 0.5 s" node -e "const d = parseFloat(process.argv[1]); process.exit(d >= 2.5 && d <= 3.5 ? 0 : 1)" "${dur:-0}"
newest() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -r '.summaries[0]'; }
newest_is() { [ "$(newest)" = "$1" ]; }
until_ok 3000 newest_is "Recording saved"
check "a notice says the recording was saved ($(newest))" newest_is "Recording saved"

# record_full: opens the picker and records the whole output.
record_full() {
  mod_shift_r
  until_ok 3000 state_is '.picking'
  wtype f
  wtype -k Return
}
# A wf-recorder that cannot write its file used to leave no trace but a vanished timer.
chmod a-w "$DOTS_RECORDINGS_DIR"
record_full
until_ok 5000 newest_is "Recording failed"
check "a recorder that cannot write its file stops, and a notice says it failed ($(newest))" bash -c '[ "$(timeout 0.5 qs ipc call notifs state | jq -r ".summaries[0]")" = "Recording failed" ] && ! pgrep -f "[w]f-recorder.*$DOTS_RECORDINGS_DIR" >/dev/null'
chmod u+w "$DOTS_RECORDINGS_DIR"

# A wf-recorder that ignores SIGINT used to keep the recorder recording for good.
touch "$DOTS_DEV_DIR/wf-recorder-stuck"
record_full
until_ok 3000 state_is '.recording'
mod_shift_r
until_ok 8000 state_is '.recording | not'
check "a recorder that ignores the stop is killed within 8 s ($(rec_state | jq -c .recording))" state_is '.recording | not'
until_ok 2000 newest_is "Recording stopped by force"
check "and a notice says it was stopped by force ($(newest))" newest_is "Recording stopped by force"
rm -f "$DOTS_DEV_DIR/wf-recorder-stuck"

exit $((fails > 0))
}
