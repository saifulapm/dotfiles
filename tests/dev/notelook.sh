#!/usr/bin/env bash
# Notes draws each theme's design: an empty Notes shows one line of keys, and the selected card is outlined in the accent.
{
source "$(dirname "$0")/lib.sh"

notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
notes_is() { notes_state | jq -e "$1" >/dev/null; }
notes_focused() { niri msg -j windows | jq -e 'any(.[]; .title == "Notes" and .is_focused)' >/dev/null; }
# The pixels of a 7 px strip across the selected card's left edge, one "r g b" per line; niri's window offset can lag a theme switch by a few px.
edge_rgbs() {
  local win rect
  win=$(niri msg -j windows | jq -c '.[] | select(.title == "Notes") | .layout | [(.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]), (.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1])]')
  rect=$(notes_state | jq -c .selectedRect)
  grim -t ppm -g "$(jq -rn --argjson w "$win" --argjson r "$rect" '"\(($w[0] + $r.x - 3) | floor),\(($w[1] + $r.y + $r.height / 2) | floor) 7x1"')" - |
    node -e 'const b = require("fs").readFileSync(0); const h = b.toString("latin1").match(/^P6\s+\d+\s+\d+\s+\d+\s/)[0].length; for (let i = h; i + 2 < b.length; i += 3) console.log(b[i], b[i + 1], b[i + 2]);'
}
near() { (($1 - $2 < 9 && $2 - $1 < 9)); }
is_accent() {
  local r g b
  while read -r r g b; do
    near "$r" "$((16#${1:1:2}))" && near "$g" "$((16#${1:3:2}))" && near "$b" "$((16#${1:5:2}))" && return 0
  done < <(edge_rgbs)
  echo "     no accent pixel across the edge: $(edge_rgbs | tr '\n' '|')"
  return 1
}

until_ok 5000 bash -c 'timeout 0.5 qs ipc call notes state >/dev/null 2>&1'
niri msg action spawn -- dots-call notes toggle
until_ok 3000 notes_focused
check "an empty Notes shows exactly one line in its list" notes_is '.emptyLine.lines == 1'
check "and it names section and attach" notes_is '.emptyLine.text | test("section.*attach"; "i")'

wtype 'the island grows down'
wtype -k Return
until_ok 2000 notes_is '.count == 1'
wtype -k Tab
until_ok 2000 notes_is '.selectedRect != null'
check "the selected card is outlined in Paper's #C8381E" is_accent '#C8381E'
for t in artboard:#3D5AFE blueprint:#7FE3F0; do
  "$repo/bin/dots" theme "${t%%:*}" >/dev/null 2>&1
  until_ok 2000 bash -c "timeout 0.5 qs ipc call shell status | jq -e '.theme == \"${t%%:*}\"' >/dev/null"
  sleep 0.3
  check "the selected card is outlined in ${t%%:*}'s ${t#*:}" is_accent "${t#*:}"
done

exit $((fails > 0))
}
