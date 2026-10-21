#!/usr/bin/env bash
# A file notification draws its chip in the toast and the centre row, and its drag drops the file's URI on another window; one with no file drops its body.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
note_is() { island | jq -e "$1" >/dev/null; }
centre() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
centre_is() { centre | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 2000 status_theme "$1"; }
open_centre() { niri msg action spawn -- dots-call notifs toggle; until_ok 3000 centre_is '.open and .settled and .cursorBox != null'; }
close_centre() { niri msg action spawn -- dots-call notifs toggle; until_ok 2000 centre_is '.open == false and .drawing == false'; }
# Pixels of geometry $1 within $5 of r g b; with_cursor=1 takes the pointer and its drag image too.
near() {
  grim ${with_cursor:+-c} -s 1 -t ppm -g "$1" - | node -e '
    const b = require("fs").readFileSync(0), [r, g, bl, tol] = process.argv.slice(1).map(Number);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/), px = b.subarray(head[0].length);
    let n = 0;
    for (let i = 0; i < head[1] * head[2]; i++) if (Math.abs(px[i * 3] - r) <= tol && Math.abs(px[i * 3 + 1] - g) <= tol && Math.abs(px[i * 3 + 2] - bl) <= tol) n++;
    console.log(n);
  ' "$2" "$3" "$4" "$5"
}
geo() { jq -r '"\(.x | floor),\(.y | floor) \(.w | floor)x\(.h | floor)"' <<<"$1"; }
rgb() { echo "$((16#${1:1:2})) $((16#${1:3:2})) $((16#${1:5:2}))"; }

# DOTS_DEV_DIR sits under /tmp/, whose files are never a notification's file, so the check's files live under the cache.
files=$HOME/.cache/dots-notif-drag-${DOTS_DEV_DIR##*-}/Downloads
mkdir -p "$files"
heic=$files/IMG_2041.HEIC
odd="$files/my photo #1 é.jpg"
printf 'heic' >"$heic"
printf 'jpg' >"$odd"
cleanup() {
  exec 7>&- 2>/dev/null
  kill "$target" "$ptr" 2>/dev/null
  rm -rf "${files%/Downloads}"
}

# The virtual pointer is built for this run; one process holds the button from press to release.
b=$DOTS_DEV_DIR/pointer
mkdir -p "$b"
wayland-scanner client-header "$repo/dev/wlr-virtual-pointer-unstable-v1.xml" "$b/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$repo/dev/wlr-virtual-pointer-unstable-v1.xml" "$b/protocol.c"
gcc -I"$b" -o "$b/pointer" "$repo/dev/pointer.c" "$b/protocol.c" -lwayland-client || exit 1
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
mkfifo "$b/in"
"$b/pointer" "$ow" "$oh" <"$b/in" >"$b/log" 2>&1 &
ptr=$!
exec 7>"$b/in"
done_count() { grep -c "^done $1" "$b/log"; }
# until_ok runs its command each poll, so each count is read inside a function, never expanded once in its arguments.
done_more() { test "$(done_count "$1")" -gt "$2"; }
# Runs one pointer line and waits for the tool to report it done.
point() {
  local n
  n=$(done_count "$1")
  echo "$*" >&7
  until_ok 15000 done_more "$1" "$n"
}

export DROP_OUT=$DOTS_DEV_DIR/drops.json
env -u QS_CONFIG_PATH qs -p "$repo/dev/drop-target.qml" >"$DOTS_DEV_DIR/drop-target.log" 2>&1 &
target=$!
target_up() { niri msg -j windows | jq -e 'any(.[]; .title == "drop-target")' >/dev/null; }
until_ok 5000 target_up
niri msg action maximize-column
# The target spans the output below the island once its column is maximized; the drop goes to its lower left.
tx=$((ow / 4))
ty=$((oh * 2 / 3))
drops() { jq -c ".[$1] // null" "$DROP_OUT" 2>/dev/null; }
drop_count() { jq length "$DROP_OUT" 2>/dev/null || echo 0; }
drops_more() { test "$(drop_count)" -gt "$1"; }
since_more() { test $(($(now_ms) - $1)) -gt "$2"; }

# Presses the middle of box $1, crosses the drag threshold, then drops on the target.
drag_to_target() {
  local x y n
  x=$(jq -r '(.x + .w / 2) | floor' <<<"$1")
  y=$(jq -r '(.y + .h / 2) | floor' <<<"$1")
  n=$(drop_count)
  point press "$x" "$y"
  point move "$((x + 30))" "$((y + 30))" 10
  point move "$tx" "$ty" 30
  point sleep 300
  point release
  until_ok 3000 drops_more "$n"
}
send_files() { notify-send -a Tailscale -h "string:x-dots-files:$1" "Taildrop · 1 file" "${1##*/}"; }
toast_for() { until_ok 3000 note_is ".mode == \"notification\" and .note.summary == \"$1\" and .animating == false"; }

in_theme paper
send_files "$heic"
toast_for "Taildrop · 1 file"
check "the toast draws a chip reading HEIC ($(island | jq -c .note.chip))" note_is '.note.chip == "HEIC"'
drag_to_target "$(island | jq -c .note.chipBox)"
check "the toast's chip drops exactly file://$heic and CRLF as text/uri-list ($(drops -1))" test "$(drops -1 | jq -r .uriList)" = "file://$heic"$'\r'
check "and offers no text/plain" bash -c "jq -e '.[-1].formats | index(\"text/plain\") == null' '$DROP_OUT' >/dev/null"

notify-send -a Tailscale -h "string:x-dots-files:$odd" "Taildrop · odd" "my photo"
toast_for "Taildrop · odd"
drag_to_target "$(island | jq -c .note.chipBox)"
check "a name with a space, # and é arrives encoded ($(drops -1 | jq -c .uriList))" test "$(drops -1 | jq -r .uriList)" = "file://$files/my%20photo%20%231%20%C3%A9.jpg"$'\r'

notify-send -a mail "plain words" "the body to drop"
toast_for "plain words"
check "a notification with no file draws no chip" note_is '.note.chip == null'
drag_to_target "$(island | jq -c .note.summaryBox)"
check "its drag drops the body as text/plain and no text/uri-list ($(drops -1))" bash -c "jq -e '.[-1].text == \"the body to drop\" and (.[-1].formats | index(\"text/uri-list\") == null)' '$DROP_OUT' >/dev/null"

notify-send -a shot -h string:image-path:/tmp/dots-notif-drag-x.png "temp image" "a temp body"
toast_for "temp image"
check "an image-path under /tmp/ draws no chip" note_is '.note.chip == null'
drag_to_target "$(island | jq -c .note.summaryBox)"
check "and drags its body as text ($(drops -1))" bash -c "jq -e '.[-1].text == \"a temp body\" and (.[-1].formats | index(\"text/uri-list\") == null)' '$DROP_OUT' >/dev/null"
icon=$(find /usr/share/icons -name '*.png' -print -quit)
notify-send -a icons -h "string:image-path:$icon" "theme icon" "an icon body"
toast_for "theme icon"
check "an icon theme image draws no chip ($icon)" note_is '.note.chip == null'

# The 5 s end mid-drag: the press crosses the threshold, then holds 6 s before the drop.
send_files "$heic"
toast_for "Taildrop · 1 file"
shown=$(now_ms)
chip_box=$(island | jq -c .note.chipBox)
x=$(jq -r '(.x + .w / 2) | floor' <<<"$chip_box")
y=$(jq -r '(.y + .h / 2) | floor' <<<"$chip_box")
n=$(drop_count)
point press "$x" "$y"
point move "$((x + 30))" "$((y + 60))" 10
point move "$tx" "$ty" 30
until_ok 2000 note_is '.note.dragging'
sleep 0.3
check "while dragged the toast reports the empty slot ($(island | jq -c '[.note.chipEmpty, .note.frame]'))" note_is '.note.chipEmpty and (.note.frame | .[0] == 1.5 and (.[1] | ascii_downcase) == "#c8381e")'
top=$(island | jq -c '.note.chipBox as $c | {x: ($c.x - 200), y: (.note.boxBottom - 1), w: 100, h: 1}')
frame=$(near "$(geo "$top")" 200 56 30 40)
check "the toast's bottom edge draws the 1.5 px accent frame ($frame of 100 px)" test "$frame" -gt 80
fill=$(near "$(geo "$(island | jq -c .note.chipBox)")" 250 246 236 12)
dash=$(near "$(geo "$(island | jq -c .note.chipBox)")" 241 233 216 30)
check "the chip's slot is a dashed outline, not the surface tag ($fill surface px, $dash paper px)" test "$fill" -lt 20 -a "$dash" -gt 30
image=$(with_cursor=1 near "$((tx - 30)),$((ty - 30)) 200x80" 250 246 236 6)
check "the drag image, the chip on the surface, follows the pointer ($image px)" test "$image" -gt 200
until_ok 7000 since_more "$shown" 6000
check "6 s after it showed, the toast is still shown mid-drag" note_is '.mode == "notification"'
point release
until_ok 3000 drops_more "$n"
dropped=$(now_ms)
check "the held drag dropped the file ($(drops -1 | jq -c .uriList))" test "$(drops -1 | jq -r .uriList)" = "file://$heic"$'\r'
until_ok 8000 bash -c "! timeout 0.5 qs ipc call island state | jq -e '.mode == \"notification\"' >/dev/null"
left=$(($(now_ms) - dropped))
check "the toast leaves about 5 s after the drop (${left} ms)" test "$left" -gt 4000 -a "$left" -lt 6500

# Each theme draws the chip; Paper's and Artboard's fills and Blueprint's cyan outline are only the shell's.
for t in paper:#FAF6EC:#FAF6EC artboard:#2B2F36:#FFFFFF blueprint:#7FE3F0:#0A1526; do
  IFS=: read -r name toast row <<<"$t"
  in_theme "$name"
  send_files "$heic"
  toast_for "Taildrop · 1 file"
  box=$(island | jq -c .note.chipBox)
  n=$(near "$(geo "$box")" $(rgb "$toast") 8)
  echo "     $name toast chip $box"
  check "$name: the toast's chip reads HEIC and draws $toast ($n px)" test "$(island | jq -r .note.chip)" = HEIC -a "$n" -gt 40
  open_centre
  box=$(centre | jq -c '.chips[0].box')
  n=$(near "$(geo "$box")" $(rgb "$row") 8)
  echo "     $name row chip $box"
  check "$name: the cursor row's chip reads HEIC and draws $row ($n px)" test "$(centre | jq -r '.chips[0].text')" = HEIC -a "$n" -gt 40
  check "$name: a row about no file has no chip ($(centre | jq -c '[.chips[] | .text?]'))" centre_is 'any(.chips[]; . == null)'
  close_centre
done

exit $((fails > 0))
}
