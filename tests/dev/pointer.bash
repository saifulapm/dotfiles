# Sourced after lib.sh by a mouse check: a virtual pointer built for this run, and clicks or wheel turns over a shell surface's click area by the name `shell box` knows it by.

# The virtual pointer reads press, move, release, click, dclick, wheel and sleep lines; each line it reads, it answers done.
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
}
cleanup() { pointer_stop; }
done_count() { grep -c "^done $1" "$ptr_dir/log"; }
# until_ok runs its command each poll, so each count is read inside a function, never expanded once in its arguments.
done_more() { test "$(done_count "$1")" -gt "$2"; }
# Runs one pointer line and waits for the tool to report it done.
point() {
  local n
  n=$(done_count "$1")
  echo "$*" >&7
  until_ok 15000 done_more "$1" "$n"
}

# The surfaces host fills the output from its origin, so a box is already in output pixels.
shell_box() { timeout 0.5 qs ipc call shell box "$1" 2>/dev/null; }
# The output point at a fraction across a named click area, its middle by default: "x y", or nothing when it is not drawn.
shell_spot() {
  local box
  box=$(shell_box "$1")
  [ -n "$box" ] && [ "$box" != null ] || return 1
  jq -r --argjson f "${2:-0.5}" '"\((.x + .w * $f) | floor) \((.y + .h / 2) | floor)"' <<<"$box"
}
# One left click on a named click area, at a fraction across it, its middle by default.
click_box() {
  local at
  at=$(shell_spot "$1" "${2:-0.5}") || { echo "no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}
# A click at output point x y with a modifier (shift, ctrl) held in the focused window: wtype holds it around the click, as a hand holds it before pressing.
mod_click() {
  local mod=$1 k
  shift
  wtype -M "$mod" -s 1200 -m "$mod" &
  k=$!
  sleep 0.4
  point click "$@"
  wait "$k"
}
# The pointer over a named click area, then the wheel turned $2 notches, down when positive.
wheel_box() {
  local at
  at=$(shell_spot "$1") || { echo "no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point move $at
  point wheel "$2"
}

# An App's window by its app id: tiled windows report no position, so float_app floats it at 20,20 on the output, and app_spot adds its origin to a box the App answers.
app_window_id() { niri msg -j windows | jq -r --arg a "$1" '[.[] | select(.app_id == $a)][0].id'; }
app_origin() { niri msg -j windows | jq -r --arg a "$1" '.[] | select(.app_id == $a) | .layout | "\((.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor) \((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor)"'; }
app_placed() { app_origin "$1" | grep -qx '[0-9]* [0-9]*'; }
float_app() {
  niri msg action toggle-window-floating --id "$(app_window_id "$1")"
  niri msg action move-floating-window --id "$(app_window_id "$1")" -x 20 -y 20
  until_ok 2000 app_placed "$1" || return 1
  # A window opened since wtype's last key gets niri's keymap; a Shift first hands it wtype's.
  wtype -k Shift_L
}
# The output point at a fraction across a box {x,y,w,h} in the App's window, its middle by default: "x y", or nothing when the box is null.
app_spot() {
  local fx fy
  [ -n "$2" ] && [ "$2" != null ] || return 1
  read -r fx fy <<<"$(app_origin "$1")"
  jq -r --argjson fx "$fx" --argjson fy "$fy" --argjson f "${3:-0.5}" '"\(($fx + .x + .w * $f) | floor) \(($fy + .y + .h / 2) | floor)"' <<<"$2"
}
