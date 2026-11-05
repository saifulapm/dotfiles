# Sourced after lib.sh by a mouse check: a virtual pointer built for this run, and clicks or wheel turns over a shell surface's click area by the name `shell box` knows it by.

# The virtual pointer reads press, move, release, click, wheel and sleep lines; each line it reads, it answers done.
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
# The pointer over a named click area, then the wheel turned $2 notches, down when positive.
wheel_box() {
  local at
  at=$(shell_spot "$1") || { echo "no click area named $1 is drawn"; return 1; }
  # shellcheck disable=SC2086
  point move $at
  point wheel "$2"
}
