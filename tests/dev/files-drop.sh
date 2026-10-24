#!/usr/bin/env bash
# Files dropped on Files from another app copy into the folder row under the pointer, or the folder shown, and stay where they came from; Files' own drag copies onto a folder row; 500 files drop at once.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
h=$work/home
mkdir -p "$h/Downloads/screenshots" "$h/Downloads/taildrop" "$h/Documents" "$work/chromium"
printf 'report' >"$work/chromium/report-final.pdf"
for i in $(seq 1 500); do printf '%s' "$i" >"$work/chromium/many-$i.txt"; done
printf 'mine' >"$h/Downloads/notes.txt"
printf '%s\n' "$work/chromium/report-final.pdf" >"$work/offer"
log=$work/files.log
cleanup() {
  exec 7>&- 2>/dev/null
  kill "$source" "$source500" "$ptr" 2>/dev/null
  rm -rf "$work"
}

files_state() { timeout 1 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }

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
done_more() { test "$(done_count "$1")" -gt "$2"; }
point() {
  local n
  n=$(done_count "$1")
  echo "$*" >&7
  until_ok 15000 done_more "$1" "$n"
}

# Where a window's content starts on the output, from niri's layout.
origin() { niri msg -j windows | jq -r --arg t "$1" '.[] | select(.app_id == $t or .title == $t) | .layout | "\((.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor) \((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor)"'; }

env -u QS_CONFIG_PATH DRAG_FILES="$(cat "$work/offer")" qs -p "$repo/dev/drag-source.qml" >"$DOTS_DEV_DIR/drag-source.log" 2>&1 &
source=$!
until_ok 5000 bash -c "niri msg -j windows | jq -e '[.[] | select(.title == \"drag-source\")] | length == 1' >/dev/null"
first_source=$(niri msg -j windows | jq -r '.[] | select(.title == "drag-source") | .id')
# A second source offers 500 files at once.
env -u QS_CONFIG_PATH DRAG_FILES="$(ls "$work"/chromium/many-*.txt)" qs -p "$repo/dev/drag-source.qml" >"$DOTS_DEV_DIR/drag-source-500.log" 2>&1 &
source500=$!
until_ok 5000 bash -c "niri msg -j windows | jq -e '[.[] | select(.title == \"drag-source\")] | length == 2' >/dev/null"
many_source=$(niri msg -j windows | jq -r --argjson f "$first_source" '.[] | select(.title == "drag-source" and .id != $f) | .id')
niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
# Tiled windows report no position, so both float side by side where the drag can find them: the target left, Files right of it.
win_id() { niri msg -j windows | jq -r --arg t "$1" '.[] | select(.app_id == $t or .title == $t) | .id'; }
for w in "$first_source" "$many_source" "$(win_id files)"; do niri msg action toggle-window-floating --id "$w"; done
# Floating keeps the tiled size; a pressed source is raised, so the sources are narrowed to stay clear of Files.
for w in "$first_source" "$many_source"; do
  niri msg action set-window-width --id "$w" 400
  niri msg action set-window-height --id "$w" 300
done
niri msg action move-floating-window --id "$first_source" -x 10 -y 60
niri msg action move-floating-window --id "$many_source" -x 10 -y 400
niri msg action move-floating-window --id "$(win_id files)" -x 450 -y 60
niri msg action focus-window --id "$(win_id files)"
placed() { niri msg -j windows | jq -e 'all(.[]; .layout.tile_pos_in_workspace_view != null)' >/dev/null; }
until_ok 2000 placed
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .is_focused)' >/dev/null"
wtype /down
until_ok 3000 files_is '.listed and (.folder | endswith("/Downloads"))'

# Presses $1,$2 on the output, drags to row $3 of Files (or, with "below", the listing under the rows), reads Files' state mid-drag into $hover, and drops.
drag_onto() {
  local x=$1 y=$2 box fx fy tx ty
  read -r fx fy < <(origin files)
  if [ "$3" = below ]; then
    box=$(timeout 1 qs ipc -p "$files_qml" call files box "$(files_state | jq -r '.rows[-1]')")
    tx=$((fx + $(jq -r '(.x + .w / 3) | floor' <<<"$box")))
    ty=$((fy + $(jq -r '(.y + .h * 3) | floor' <<<"$box")))
  else
    box=$(timeout 1 qs ipc -p "$files_qml" call files box "$3")
    tx=$((fx + $(jq -r '(.x + .w / 3) | floor' <<<"$box")))
    ty=$((fy + $(jq -r '(.y + .h / 2) | floor' <<<"$box")))
  fi
  point press "$x" "$y"
  point move "$((x + 30))" "$((y + 30))" 10
  point move "$tx" "$ty" 30
  point sleep 400
  hover=$(files_state | jq -c '{op: {dropping: .op.dropping, dropAt: .op.dropAt}, status, keys: .drawn}')
  point release
}
# The window's content corner from its id; both sources share a title.
corner() { niri msg -j windows | jq -r --argjson i "$1" '.[] | select(.id == $i) | .layout | "\((.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor) \((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor)"'; }
read -r sx sy < <(corner "$first_source")
sx=$((sx + 150))
sy=$((sy + 100))

drag_onto "$sx" "$sy" screenshots
check "a file dragged from the browser over screenshots/ marks it as the target ($hover)" \
  jq -e '.op.dropping and .op.dropAt == "screenshots" and .status.counts == "copy 1 file into screenshots/" and .status.at == "report-final.pdf"' <<<"$hover"
until_ok 3000 test -f "$h/Downloads/screenshots/report-final.pdf"
check "the drop copies it into screenshots/ and it stays where it came from" \
  bash -c "[ \"\$(cat '$h/Downloads/screenshots/report-final.pdf')\" = report ] && [ -f '$work/chromium/report-final.pdf' ]"
check "after the drop the status line reads the counts again" files_is '.op.dropping == false and .op.dropAt == null'

drag_onto "$sx" "$sy" below
check "over the listing below the rows, the folder shown is the target ($hover)" jq -e '.op.dropAt == null and .status.counts == "copy 1 file into Downloads/"' <<<"$hover"
until_ok 3000 test -f "$h/Downloads/report-final.pdf"
check "and the drop copies it into Downloads" bash -c "[ \"\$(cat '$h/Downloads/report-final.pdf')\" = report ]"

# Files' own drag: notes.txt onto taildrop/.
read -r fx fy < <(origin files)
box=$(timeout 1 qs ipc -p "$files_qml" call files box notes.txt)
drag_onto "$((fx + $(jq -r '(.x + .w / 3) | floor' <<<"$box")))" "$((fy + $(jq -r '(.y + .h / 2) | floor' <<<"$box")))" taildrop
until_ok 3000 test -f "$h/Downloads/taildrop/notes.txt"
check "dragging notes.txt onto taildrop/ in Files copies it there ($(jq -c .op <<<"$hover"))" bash -c "[ \"\$(cat '$h/Downloads/taildrop/notes.txt')\" = mine ] && [ -f '$h/Downloads/notes.txt' ]"

drag_onto "$sx" "$sy" screenshots
check "after Files' own drag, a drop from another app is still taken ($(jq -c .op <<<"$hover"))" jq -e '.op.dropping and .op.dropAt == "screenshots"' <<<"$hover"

read -r mx my < <(corner "$many_source")
drag_onto "$((mx + 150))" "$((my + 100))" screenshots
check "500 files dragged over screenshots/ say so ($(jq -c .status <<<"$hover"))" jq -e '.status.counts == "copy 500 files into screenshots/"' <<<"$hover"
until_ok 15000 bash -c "[ \"\$(ls '$h/Downloads/screenshots' | grep -c '^many-')\" = 500 ]"
check "and all 500 copy ($(ls "$h/Downloads/screenshots" | grep -c '^many-'))" test "$(ls "$h/Downloads/screenshots" | grep -c '^many-')" = 500

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
