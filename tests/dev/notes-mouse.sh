#!/usr/bin/env bash
# Notes by mouse: a click on a Shelf tab shows that section, a card drags its text out to another window, a click on a card edits it as Enter does, and a click on the pinned badge unpins Notes.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$@" >/dev/null 2>&1; }
notes_box() { timeout 0.5 qs ipc call notes box "$1" 2>/dev/null; }
notes_focused() { niri msg -j windows | jq -e 'any(.[]; .title == "Notes" and .is_focused)' >/dev/null; }
# Notes floats docked right, so its window reports where it is; the drop target is a qs window too, so Notes is found by its title.
notes_spot() {
  local box fx fy
  box=$(notes_box "$1")
  [ -n "$box" ] && [ "$box" != null ] || return 1
  read -r fx fy < <(niri msg -j windows | jq -r '.[] | select(.title == "Notes") | .layout | "\((.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor) \((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor)"')
  jq -r --argjson fx "$fx" --argjson fy "$fy" --argjson f "${2:-0.5}" '"\(($fx + .x + .w * $f) | floor) \(($fy + .y + .h / 2) | floor)"' <<<"$box"
}
notes_click() {
  local at
  at=$(notes_spot "$1") || { echo "no click area named $1 is drawn in Notes"; return 1; }
  # shellcheck disable=SC2086
  point click $at
}
compose() {
  local n
  n=$(notes_state | jq '.notes | length')
  wtype "$1"
  wtype -k Return
  until_ok 2000 notes_is "(.notes | length) > $n"
}

export DROP_OUT=$DOTS_DEV_DIR/drops.json
env -u QS_CONFIG_PATH qs -p "$repo/dev/drop-target.qml" >"$DOTS_DEV_DIR/drop-target.log" 2>&1 &
target=$!
cleanup() {
  pointer_stop
  kill "$target" 2>/dev/null
}
until_ok 5000 niri msg -j windows | jq -e 'any(.[]; .title == "drop-target")' >/dev/null
until_ok 5000 bash -c '[ "$(niri msg -j windows | jq -r "[.[] | select(.title == \"drop-target\")][0].is_focused")" = true ]'
niri msg action maximize-column
drop_count() { jq length "$DROP_OUT" 2>/dev/null || echo 0; }
drops_more() { test "$(drop_count)" -gt "$1"; }

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
niri msg action spawn -- dots-call notes toggle
until_ok 3000 notes_focused
wtype '# ideas'
wtype -k Return
until_ok 2000 notes_is '.section == "ideas"'
compose 'an idea to drag'
niri msg action spawn -- dots-call notes shelf
until_ok 3000 notes_is '.section == "Shelf" and (.drawnTabs | length) >= 2'
check "Shelf draws the sections as tabs ($(notes_state | jq -c '[.drawnTabs[].text]'))" notes_is '[.drawnTabs[] | select(.current)] | length == 1'
notes_click notes-tab:ideas
until_ok 2000 notes_is '.section == "ideas"'
check "a click on the ideas tab shows that section ($(notes_state | jq -c .section))" notes_is '.section == "ideas" and (.cards | length) == 1'

# The card's body drags its text to the target, filling the output left of Notes.
box=$(notes_spot notes-card:0)
read -r x y <<<"$box"
n=$(drop_count)
point press "$x" "$y"
point move "$((x - 30))" "$((y + 30))" 10
point move "$((ow / 4))" "$((oh * 2 / 3))" 30
point sleep 300
point release
until_ok 3000 drops_more "$n"
check "a card dragged onto another window drops its text ($(jq -c '.[-1]' "$DROP_OUT" 2>/dev/null))" bash -c "jq -e '.[-1].text == \"an idea to drag\"' '$DROP_OUT' >/dev/null"
check "and the drag left the card as it was, not opened to edit" notes_is '.editing == null or .editing == ""'

niri msg action spawn -- dots-call notes open
until_ok 3000 notes_focused
n=$(drop_count)
notes_click notes-card:0
until_ok 2000 notes_is '.mode == "composer" and .composer == "an idea to drag"'
check "a click on the card edits it, as Enter does ($(notes_state | jq -c '{mode, composer}'))" notes_is '.mode == "composer" and .composer == "an idea to drag" and (.editing | length) > 0'
check "and drops nothing" test "$(drop_count)" = "$n"
wtype -k Escape

niri msg action spawn -- dots-call notes pin
until_ok 3000 notes_is '.pinned'
until_ok 2000 bash -c "[ \"\$(timeout 0.5 qs ipc call notes box notes-pin)\" != null ]"
notes_click notes-pin
until_ok 2000 notes_is '.pinned == false'
check "a click on the pinned badge unpins Notes" notes_is '.pinned == false'

exit "$fails"
}
