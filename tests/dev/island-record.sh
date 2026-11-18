#!/usr/bin/env bash
# Mod+Shift+R grows the island into the Recorder's 400 x 64 bar over a full-output dim: the region's handles resize it, Start records it, and Cancel or Esc records nothing.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

rec_state() { timeout 0.5 qs ipc call record state 2>/dev/null; }
rec_is() { rec_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
px() { grim -g "$1,$2 1x1" -t ppm - 2>/dev/null | tail -c3 | od -An -tx1 | tr -d ' \n'; }
px_is() { [ "$(px "$1" "$2")" = "$3" ]; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_shift_r() { niri msg action spawn -- dots-call record toggle; }
files() { find "$DOTS_RECORDINGS_DIR" -name '*.mp4' 2>/dev/null | wc -l; }
# Only this session's recorder writes into its own recordings dir; sh execs it, so the count settles on one process per recording.
recorders() { pgrep -c -f "[w]f-recorder -y .*$DOTS_RECORDINGS_DIR"; }
no_recorder() { ! pgrep -f "[w]f-recorder -y .*$DOTS_RECORDINGS_DIR" >/dev/null; }
at_rest() { island_is '.surface == null and .animating == false'; }
open_bar() {
  mod_shift_r
  until_ok 3000 rec_is '.picking and .settled'
  until_ok 3000 island_is '.surface == "record" and .animating == false'
}
# One left click in the middle of a bar button, by its box in record state.
click_bar() {
  local at
  at=$(rec_state | jq -r --arg b "$1" '.[$b] | "\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"')
  # shellcheck disable=SC2086
  point click $at
}
# A drag with the left button from x1 y1 to x2 y2, in ten steps.
drag() {
  point press "$1" "$2"
  point move "$3" "$4" 10
  point release
}
white=
cleanup() {
  pointer_stop
  [ -z "$white" ] || niri msg action close-window --id "$white" 2>/dev/null
}

until_ok 5000 shell_status >/dev/null
until_ok 5000 at_rest
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
echo "     output ${ow}x${oh}"

# A plain white window under the dim, so the dim and the clear region read as known pixels.
niri msg action spawn -- foot -c /dev/null -o colors-dark.background=ffffff -o colors-dark.foreground=ffffff -o colors-light.background=ffffff -o colors-light.foreground=ffffff -T record-white sleep 600
white_id() { niri msg -j windows | jq -e -r '.[] | select(.title == "record-white") | .id'; }
until_ok 5000 white_id >/dev/null
white=$(white_id)
niri msg action fullscreen-window --id "$white"
until_ok 3000 px_is $((ow / 8)) $((oh / 2)) ffffff
check "the white window reads ffffff before the picker opens ($(px $((ow / 8)) $((oh / 2))))" px_is $((ow / 8)) $((oh / 2)) ffffff

open_bar
check "Mod+Shift+R sets surface to record and the island 400 x 64 ($(island | jq -c '{surface, width, height}'))" island_is '.surface == "record" and .width == 400 and .height == 64'
check "the region is drawn in the middle, outside it dimmed: $(px $((ow / 8)) $((oh / 2))) outside, $(px $((ow / 2)) $((oh / 2))) inside" bash -c '[ "$1" = 949494 ] && [ "$2" = ffffff ]' _ "$(px $((ow / 8)) $((oh / 2)))" "$(px $((ow / 2)) $((oh / 2)))"
niri msg action close-window --id "$white"
white=

# A plain drag draws a new region; its bottom-right handle then resizes it from that corner.
drag 40 40 440 340
check "a drag from 40,40 to 440,340 draws a 400 x 300 region ($(rec_state | jq -c .region))" rec_is '.region == {x: 40, y: 40, w: 400, h: 300}'
drag 440 340 840 640
check "dragging its bottom-right handle to 840,640 makes it 800 x 600 ($(rec_state | jq -c .region))" rec_is '.region == {x: 40, y: 40, w: 800, h: 600}'
check "and the bar reads 800 × 600 ($(rec_state | jq -c .size))" rec_is '.size == "800 × 600"'

# Start records the region; the island goes live with the red record icon.
click_bar start
until_ok 3000 rec_is '.recording'
check "a click on Start begins recording" rec_is '.recording and (.picking | not)'
rec_drawn() { island | jq -e --arg i "$(printf '\U000F044A')" '(.text | startswith("REC")) and .live.icon == $i and (.live.text | test("^00:0[0-9]$")) and .live.tone == "danger"' >/dev/null; }
until_ok 3000 rec_drawn
check "the island reads REC with a red record icon and 00:0x ($(island | jq -c '{text, live}'))" rec_drawn
check "the dim is gone" rec_is '.drawing == false'
sleep 1
mod_shift_r
until_ok 5000 rec_is '.recording | not'
until_ok 3000 no_recorder
check "Mod+Shift+R again stops it and one file is saved ($(files))" test "$(files)" = 1

# Esc and Cancel each clear the dim and return the island to rest, recording nothing.
open_bar
wtype -k Escape
until_ok 3000 rec_is '.drawing == false'
until_ok 3000 at_rest
cleared() { rec_is '.drawing == false and (.picking | not)' && at_rest; }
check "Esc clears the dim and returns the island to rest ($(island | jq -c .surface))" cleared
open_bar
click_bar cancel
until_ok 3000 rec_is '.drawing == false'
until_ok 3000 at_rest
check "a click on Cancel clears the dim and returns the island to rest ($(island | jq -c .surface))" cleared
sleep 0.5
nothing_more() { [ "$(files)" = 1 ] && no_recorder; }
check "neither started wf-recorder nor wrote a file ($(files))" nothing_more

# A region dragged under 16 px wide stays 16 px; Enter twice starts one recording.
open_bar
drag 100 100 105 200
check "a drag 5 px wide makes a region 16 px wide ($(rec_state | jq -c .region))" rec_is '.region.w == 16 and .region.h == 100'
wtype -k Return -s 100 -k Return
until_ok 3000 rec_is '.recording'
sleep 1
check "Enter twice runs one wf-recorder ($(recorders))" test "$(recorders)" = 1
mod_shift_r
until_ok 5000 rec_is '.recording | not'
until_ok 3000 no_recorder
check "and saves one more file ($(files))" test "$(files)" = 2

exit $((fails > 0))
}
