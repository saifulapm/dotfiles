# Sourced after lib.sh by Dekho's mouse checks: opens Dekho floating where the virtual pointer can find it, and clicks or turns the wheel over a click area by the name `dekho box` knows it by.

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
log=$work/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_box() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho box "$1" 2>/dev/null; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_id() { niri msg -j windows | jq -r '[.[] | select(.app_id == "dekho")][0].id'; }

# The virtual pointer is built for this run; each line it reads, it answers done.
ptr_dir=$DOTS_DEV_DIR/pointer
mkdir -p "$ptr_dir"
wayland-scanner client-header "$repo/dev/wlr-virtual-pointer-unstable-v1.xml" "$ptr_dir/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$repo/dev/wlr-virtual-pointer-unstable-v1.xml" "$ptr_dir/protocol.c"
gcc -I"$ptr_dir" -o "$ptr_dir/pointer" "$repo/dev/pointer.c" "$ptr_dir/protocol.c" -lwayland-client || exit 1
read -r ow oh < <(niri msg -j outputs | jq -r '.[] | .logical | "\(.width) \(.height)"')
mkfifo "$ptr_dir/in"
"$ptr_dir/pointer" "$ow" "$oh" <"$ptr_dir/in" >"$ptr_dir/log" 2>&1 &
ptr=$!
exec 7>"$ptr_dir/in"
# A check's own cleanup calls this first.
pointer_stop() {
  exec 7>&- 2>/dev/null
  kill "$ptr" 2>/dev/null
  rm -rf "$work"
}
cleanup() { pointer_stop; }
done_count() { grep -c "^done $1" "$ptr_dir/log"; }
done_more() { test "$(done_count "$1")" -gt "$2"; }
point() {
  local n
  n=$(done_count "$1")
  echo "$*" >&7
  until_ok 15000 done_more "$1" "$n"
}

# Tiled windows report no position, so Dekho floats at 20,20 on the output, where its content starts.
dekho_at=
open_dekho() {
  niri msg action spawn -- sh -c "exec $(sed -n 's/^Exec=//p' "$entry") >>'$log' 2>&1"
  until_ok 5000 dekho_up || return 1
  niri msg action toggle-window-floating --id "$(dekho_id)"
  niri msg action move-floating-window --id "$(dekho_id)" -x 20 -y 20
  until_ok 2000 dekho_placed || return 1
  dekho_at=$(dekho_origin)
  # A window opened since wtype's last key gets niri's keymap; a Shift first hands it wtype's.
  wtype -k Shift_L
}
dekho_origin() { niri msg -j windows | jq -r '.[] | select(.app_id == "dekho") | .layout | "\((.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor) \((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor)"'; }
dekho_placed() { dekho_origin | grep -qx '[0-9]* [0-9]*'; }

# The output point at a fraction of a click area, its middle by default: "x y", or nothing when it is not drawn.
spot() {
  local box fx fy
  box=$(dekho_box "$1")
  [ -n "$box" ] && [ "$box" != null ] || return 1
  read -r fx fy <<<"$dekho_at"
  jq -r --argjson fx "$fx" --argjson fy "$fy" --argjson f "${2:-0.5}" '"\(($fx + .x + .w * $f) | floor) \(($fy + .y + .h / 2) | floor)"' <<<"$box"
}
# One left click in the middle of a named click area.
click_on() {
  local at
  at=$(spot "$1") || { echo "no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}
# The pointer over a named click area, then the wheel turned $2 notches, down when positive.
wheel_on() {
  local at
  at=$(spot "$1") || { echo "no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point move $at
  point wheel "$2"
}
export -f dekho_state dekho_is
export dekho_qml
