#!/usr/bin/env bash
# A GTK4 widget's box: null with box_reason "no window position" while its window is tiled, where niri gives no position; once the window floats, a box inside the window's rectangle on screen, never 0,0.
{
source "$(dirname "$0")/lib.sh"

scripts=$repo/home/dot_claude/skills/desktop/scripts
gui=$scripts/gui
cleanup() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id'); do
    niri msg action close-window --id "$id" 2>/dev/null
  done
  return 0
}

niri msg action spawn -- gtk4-widget-factory
until_ok 15000 bash -c "'$gui' find gtk4-widget-factory Lorem >/dev/null 2>&1"
id=$(niri msg -j windows | jq '.[] | select(.app_id == "org.gtk.WidgetFactory4") | .id')
"$gui" tree gtk4-widget-factory >"$DOTS_DEV_DIR/tiled.json"
check "tiled, every box is null with box_reason no window position" jq -e 'all(.nodes[]; .box == null and .box_reason == "no window position")' "$DOTS_DEV_DIR/tiled.json"
button=$(jq -r '[.nodes[] | select(.role == "button" and .name != "")][0].ref' "$DOTS_DEV_DIR/tiled.json")
out=$("$gui" get gtk4-widget-factory "$button" box)
check "and gui get box says the same: $out" jq -e '.box == null and .box_reason == "no window position"' <<<"$out"

niri msg action toggle-window-floating --id "$id"
placed() { niri msg -j windows | jq -e ".[] | select(.id == $id) | .layout.tile_pos_in_workspace_view != null" >/dev/null; }
until_ok 3000 placed
# The window's rectangle on screen: its output's origin, its tile's place in the workspace and the window's offset in the tile.
rect=$(jq -nc --argjson w "$(niri msg -j windows | jq ".[] | select(.id == $id)")" --argjson ws "$(niri msg -j workspaces)" --argjson o "$(niri msg -j outputs)" '
  ($ws[] | select(.id == $w.workspace_id) | .output) as $out | $o[$out].logical as $l |
  {x: ($l.x + $w.layout.tile_pos_in_workspace_view[0] + $w.layout.window_offset_in_tile[0]), y: ($l.y + $w.layout.tile_pos_in_workspace_view[1] + $w.layout.window_offset_in_tile[1]), w: $w.layout.window_size[0], h: $w.layout.window_size[1]}')
button=$("$gui" tree gtk4-widget-factory | jq -r '[.nodes[] | select(.role == "button" and .name != "")][0].ref')
out=$("$gui" get gtk4-widget-factory "$button" box)
check "floating, a named button's box ($out) lies inside the window's rectangle $rect" jq -e --argjson r "$rect" '.box as [$x, $y, $w, $h] | $w > 0 and $h > 0 and $x >= $r.x and $y >= $r.y and $x + $w <= $r.x + $r.w + 1 and $y + $h <= $r.y + $r.h + 1 and ($x + $y) > 0 and (has("box_reason") | not)' <<<"$out"

exit $((fails > 0))
}
