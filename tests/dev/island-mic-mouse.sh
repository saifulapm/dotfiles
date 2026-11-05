#!/usr/bin/env bash
# A click on the mic slot focuses the recording app's window: the window of the recording process or its nearest parent, and of two windows of that process, the one focused last; a recorder with no window changes no focus, whatever process its stream claims.
{
export DOTS_DEV_WIREPLUMBER=1
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

rec=
cleanup() {
  pointer_stop
  [ -z "$rec" ] || kill "$rec" 2>/dev/null
}
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
reads() { [ "$(island | jq -r .text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
island_spot() {
  local box
  box=$(timeout 0.5 qs ipc call island box "$1" 2>/dev/null)
  [ -n "$box" ] && [ "$box" != null ] || return 1
  jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"' <<<"$box"
}
click_island() {
  local at
  at=$(island_spot island) || { echo "no island click area is drawn"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}
win_id() { niri msg -j windows | jq -r --arg t "$1" 'first(.[] | select(.title == $t) | .id) // empty'; }
has_win() { [ -n "$(win_id "$1")" ]; }
focused_title() { niri msg -j windows | jq -r 'first(.[] | select(.is_focused) | .title) // ""'; }
focused_is() { [ "$(focused_title)" = "$1" ]; }
# niri stamps a focus only once it has held past its debounce, so each focus is held a moment.
focus() {
  niri msg action focus-window --id "$(win_id "$1")"
  until_ok 2000 focused_is "$1"
  sleep 1.2
}

until_ok 5000 shell_status >/dev/null
until_ok 2000 mode_is rest

# One foot server owns two windows, and records through a child, as chromium's browser process owns its windows and records through a child; a third window is another process.
niri msg action spawn -- sh -c 'pw-record -P "{ application.name = Chromium node.name = test-chromium }" --raw - >/dev/null 2>&1 & exec foot -c /dev/null --server'
until_ok 3000 test -S "$XDG_RUNTIME_DIR/foot-$WAYLAND_DISPLAY.sock"
niri msg action spawn -- footclient -T one
niri msg action spawn -- footclient -T two
niri msg action spawn -- foot -c /dev/null -T other
until_ok 5000 has_win one
until_ok 5000 has_win two
until_ok 5000 has_win other
until_ok 3000 reads "● MIC · Chromium"
check "the recording foot server reads ● MIC · Chromium ($(island | jq -r .text))" reads "● MIC · Chromium"
server=$(niri msg -j windows | jq -r 'first(.[] | select(.title == "one") | .pid)')
check "both foot windows are the server's process ($(niri msg -j windows | jq -c '[.[] | {title, pid}]'))" test "$(niri msg -j windows | jq --argjson p "$server" '[.[] | select(.pid == $p)] | length')" -eq 2

focus one
focus two
focus other
click_island
until_ok 2000 focused_is two
check "a click on the mic slot focuses the recording process's window focused last ($(focused_title))" focused_is two

focus one
focus other
click_island
until_ok 2000 focused_is one
check "after the other window had the focus last, the click focuses that one ($(focused_title))" focused_is one

# A recorder with no window of its own, or of a parent's, leaves the focus where it is, though its stream claims other's process.
niri msg action close-window --id "$(win_id one)"
niri msg action close-window --id "$(win_id two)"
until_ok 3000 bash -c "! niri msg -j windows | jq -e 'any(.[]; .title == \"two\")' >/dev/null"
# shellcheck disable=SC2046
kill $(pgrep -P "$server") "$server" 2>/dev/null
until_ok 3000 mode_is rest
check "the foot server's recorder has ended ($(island | jq -r .text))" mode_is rest
niri msg action spawn -- foot -c /dev/null -T plain
until_ok 5000 has_win plain
other_pid=$(niri msg -j windows | jq -r 'first(.[] | select(.title == "other") | .pid)')
pw-record -P "{ application.name = Loner node.name = test-loner application.process.id = $other_pid }" --raw - >/dev/null 2>&1 &
rec=$!
until_ok 3000 reads "● MIC · Loner"
check "a windowless recorder claiming other's process reads ● MIC · Loner ($(island | jq -r .text))" reads "● MIC · Loner"
focus plain
click_island
until_ok 1000 bash -c "! [ \"\$(niri msg -j windows | jq -r 'first(.[] | select(.is_focused) | .title) // \"\"')\" = plain ]"
check "a click on it keeps the focus on plain, not the claimed other ($(focused_title))" focused_is plain

exit $((fails > 0))
}
