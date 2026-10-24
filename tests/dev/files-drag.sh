#!/usr/bin/env bash
# Dragging a marked row out of Files drops every marked file's URI on another window as text/uri-list; any other row drops only itself.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
h=$work/home
mkdir -p "$h/Downloads"
for n in IMG_2039.jpg IMG_2040.jpg IMG_2041.jpg "my photo #1 é.jpg"; do printf 'jpg' >"$h/Downloads/$n"; done
log=$work/files.log
cleanup() {
  exec 7>&- 2>/dev/null
  kill "$target" "$ptr" 2>/dev/null
  rm -rf "$work"
}

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
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

export DROP_OUT=$DOTS_DEV_DIR/drops.json
env -u QS_CONFIG_PATH qs -p "$repo/dev/drop-target.qml" >"$DOTS_DEV_DIR/drop-target.log" 2>&1 &
target=$!
until_ok 5000 bash -c "niri msg -j windows | jq -e 'any(.[]; .title == \"drop-target\")' >/dev/null"
niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
# Tiled windows report no position, so both float side by side where the drag can find them: the target left, Files right of it.
win_id() { niri msg -j windows | jq -r --arg t "$1" '.[] | select(.app_id == $t or .title == $t) | .id'; }
for w in drop-target files; do niri msg action toggle-window-floating --id "$(win_id "$w")"; done
niri msg action move-floating-window --id "$(win_id drop-target)" -x 10 -y 60
niri msg action set-window-width --id "$(win_id drop-target)" 400
niri msg action move-floating-window --id "$(win_id files)" -x 450 -y 60
niri msg action focus-window --id "$(win_id files)"
placed() { [ "$(origin files)" != "" ] && [ "$(origin drop-target)" != "" ] && ! origin files | grep -q null; }
until_ok 2000 placed
drops() { jq -c ".[$1] // null" "$DROP_OUT" 2>/dev/null; }
drop_count() { jq length "$DROP_OUT" 2>/dev/null || echo 0; }
drops_more() { test "$(drop_count)" -gt "$1"; }

# Presses the middle of row $1, crosses the drag threshold, then drops in the middle of the drop target.
drag_row() {
  local box fx fy x y tx ty n
  box=$(timeout 0.5 qs ipc -p "$files_qml" call files box "$1")
  read -r fx fy < <(origin files)
  x=$((fx + $(jq -r '(.x + .w / 3) | floor' <<<"$box")))
  y=$((fy + $(jq -r '(.y + .h / 2) | floor' <<<"$box")))
  read -r tx ty < <(origin drop-target)
  tx=$((tx + 150))
  ty=$((ty + 200))
  n=$(drop_count)
  # A drop focuses the window it lands on, so Files is focused again before each drag.
  niri msg action focus-window --id "$(win_id files)"
  point press "$x" "$y"
  point move "$((x + 30))" "$((y + 30))" 10
  until_ok 2000 files_is '.dragging'
  dragging_seen=$(files_state | jq -c '{chip, status}')
  point move "$tx" "$ty" 30
  point sleep 300
  point release
  until_ok 3000 drops_more "$n"
}

wtype jjj
until_ok 1000 files_is '.cursor == "Downloads"'
wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
wtype -k space -k space
until_ok 1000 files_is '.marked == ["IMG_2039.jpg", "IMG_2040.jpg"]'

drag_row IMG_2040.jpg
check "while a marked row drags, the chip reads 2 files and the status line says so ($dragging_seen)" \
  jq -e '.chip == "2 files" and .status.counts == "2 marked · 6 B" and .status.at == "dragging"' <<<"$dragging_seen"
# $() drops the last \n, so the list read back ends in \r.
want="file://$h/Downloads/IMG_2039.jpg"$'\r\n'"file://$h/Downloads/IMG_2040.jpg"$'\r'
check "dragging a marked row drops both marked files as text/uri-list ($(drops -1 | jq -c .uriList))" test "$(drops -1 | jq -r .uriList)" = "$want"
until_ok 2000 files_is '.dragging == false'
check "after the drop the status line reads the counts again ($(files_state | jq -c .status.at))" files_is '.dragging == false and .status.at != "dragging"'

drag_row "my photo #1 é.jpg"
check "dragging an unmarked row drops only it, its name encoded ($(drops -1 | jq -c .uriList))" \
  test "$(drops -1 | jq -r .uriList)" = "file://$h/Downloads/my%20photo%20%231%20%C3%A9.jpg"$'\r'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
