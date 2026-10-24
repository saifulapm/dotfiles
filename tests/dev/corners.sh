#!/usr/bin/env bash
# The pointer pushed into the top-right corner opens Notes, or focuses it when open; niri's bottom-left corner toggles the overview, and top-left does nothing.
{
source "$(dirname "$0")/lib.sh"

# The virtual pointer is built for this run.
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
cleanup() {
  exec 7>&- 2>/dev/null
  kill "$ptr" 2>/dev/null
}
done_count() { grep -c "^done $1" "$b/log"; }
done_more() { test "$(done_count "$1")" -gt "$2"; }
point() {
  local n
  n=$(done_count "$1")
  echo "$*" >&7
  until_ok 15000 done_more "$1" "$n"
}

notes_is() { timeout 0.5 qs ipc call notes state 2>/dev/null | jq -e "$1" >/dev/null; }
overview_open() { niri msg -j overview-state | jq -e '.is_open' >/dev/null; }
right=$((ow - 1))
bottom=$((oh - 1))

niri msg action spawn -- foot -c /dev/null
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot" and .is_focused)' >/dev/null; }
until_ok 5000 foot_focused

point move $((ow / 2)) $((oh / 2)) 1
point move "$right" 0 10
until_ok 3000 notes_is '.open and .focused'
check "the top-right corner opens Notes, focused" notes_is '.open and .focused'

# Away and back with foot focused: the corner brings the open Notes forward, and never closes it.
point move $((ow / 2)) $((oh / 2)) 10
niri msg action focus-window --id "$(niri msg -j windows | jq '.[] | select(.app_id == "foot") | .id')"
until_ok 2000 foot_focused
point move "$right" 0 10
until_ok 3000 notes_is '.open and .focused'
check "the corner focuses Notes when it is open behind foot" notes_is '.open and .focused'
point move $((ow / 2)) $((oh / 2)) 10
point move "$right" 0 10
point sleep 300
check "the corner leaves a focused Notes open" notes_is '.open and .focused'

point move $((ow / 2)) $((oh / 2)) 10
point move 0 "$bottom" 10
until_ok 3000 overview_open
check "the bottom-left corner opens the overview" overview_open
niri msg action close-overview
until_ok 2000 bash -c '! niri msg -j overview-state | jq -e .is_open >/dev/null'

point move $((ow / 2)) $((oh / 2)) 10
point move 0 0 10
point sleep 500
check "the top-left corner does nothing" bash -c '! niri msg -j overview-state | jq -e .is_open >/dev/null'

exit $((fails > 0))
}
