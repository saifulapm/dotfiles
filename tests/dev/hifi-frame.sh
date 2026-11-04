#!/usr/bin/env bash
# In Hi-Fi niri glows amber around the focused window only, and an open foot wears Gruvbox Dark on `dots colorscheme gruvbox-dark` and Artboard's white on `dots colorscheme artboard`.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
focus_id() { niri msg -j focused-window | jq -r .id; }
foot_count() { test "$(niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length')" = 2; }
# Left and right edge x, and the vertical middle, of window $1 on the output.
edges() { niri msg -j windows | jq -r --argjson id "$1" '.[] | select(.id == $id) | .layout | (.tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) as $x | (.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) as $y | "\($x | floor) \($x + .window_size[0] | floor) \(($y + .window_size[1] / 2) | floor)"'; }
pixel() { grim -s 1 -t ppm -g "$1,$2 1x1" - | mean_rgb; }
# Red minus blue at a pixel.
warmth() { local r g b; read -r r g b < <(pixel "$1" "$2"); echo $((r - b)); }

# Window 1 prints a line of ANSI colour 1 cells, which foot repaints when its palette changes.
niri msg action spawn -- foot -c /dev/null sh -c 'printf "\033[41m%60s\033[0m\n" ""; sleep 300'
until_ok 5000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"foot\")" >/dev/null'
niri msg action spawn -- foot -c /dev/null
until_ok 5000 foot_count
id1=$(niri msg -j windows | jq -r 'sort_by(.id) | [.[] | select(.app_id == "foot")][0].id')
id2=$(niri msg -j windows | jq -r 'sort_by(.id) | [.[] | select(.app_id == "foot")][1].id')
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')

legacy_theme hi-fi

# niri reports a tiled window's place only when it floats, so the two sit side by side as floating windows, 100 px apart; the spots 4 px out of their outer edges are far from the other window's glow.
for id in "$id1" "$id2"; do
  niri msg action toggle-window-floating --id "$id"
  niri msg action set-window-width --id "$id" 600
  niri msg action set-window-height --id "$id" 500
done
niri msg action move-floating-window --id "$id1" -x 300 -y 300
niri msg action move-floating-window --id "$id2" -x 1000 -y 300
niri msg action focus-window --id "$id2"
is_focused() { test "$(focus_id)" = "$1"; }
until_ok 2000 is_focused "$id2"
laid_out() { niri msg -j windows | jq -e 'all(.[]; .layout.tile_pos_in_workspace_view != null)' >/dev/null; }
until_ok 3000 laid_out
read -r l1 r1 m1 < <(edges "$id1")
read -r l2 r2 m2 < <(edges "$id2")
left_spot=$((ox + l1 - 4)) right_spot=$((ox + r2 + 4))
glow_is() { (($(warmth "$1" "$2") >= 10)); }
no_glow() { ! glow_is "$@"; }
until_ok 3000 glow_is "$right_spot" $((oy + m2))
check "the focused foot has an amber glow 4 px right of it (red - blue = $(warmth "$right_spot" $((oy + m2))))" glow_is "$right_spot" $((oy + m2))
check "the unfocused foot has none 4 px left of it (red - blue = $(warmth "$left_spot" $((oy + m1))))" no_glow $left_spot $((oy + m1))

niri msg action focus-window --id "$id1"
until_ok 2000 is_focused "$id1"
check "after focus moves, the first foot glows 4 px left of it (red - blue = $(warmth "$left_spot" $((oy + m1))))" glow_is "$left_spot" $((oy + m1))
check "and the second foot has none 4 px right of it (red - blue = $(warmth "$right_spot" $((oy + m2))))" no_glow $right_spot $((oy + m2))

# Hi-Fi's foot wore Gruvbox Dark, and only dots colorscheme reloads an open foot.
"$repo/bin/dots" colorscheme gruvbox-dark
check "the switch names no app that missed it ($(cat "$XDG_STATE_HOME/dots/theme-out/notice"))" test ! -s "$XDG_STATE_HOME/dots/theme-out/notice"
# Foot's colours are read from its pixels: low in the window is its background, and the printed cells are ANSI colour 1.
read -r fl fr _ < <(edges "$id1")
read -r fy fh < <(niri msg -j windows | jq -r --argjson id "$id1" '.[] | select(.id == $id) | .layout | "\((.tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor) \(.window_size[1])"')
bg_x=$((ox + (fl + fr) / 2)) bg_y=$((oy + fy + fh - 20))
foot_bg_is() { local r g b; read -r r g b < <(pixel "$bg_x" "$bg_y"); near "$r" "$1" && near "$g" "$2" && near "$b" "$3"; }
red_cells() {
  grim -s 1 -t ppm -g "$((ox + fl)),$((oy + fy)) $((fr - fl))x$((fh))" - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), want = [0xcc, 0x24, 0x1d];
    let n = 0;
    for (let i = 0; i < px.length; i += 3) if (want.every((v, k) => Math.abs(px[i + k] - v) <= 6)) n++;
    console.log(n);
  '
}
until_ok 1000 foot_bg_is 40 40 40
check "the open foot's background is Gruvbox Dark's #282828 ($(pixel "$bg_x" "$bg_y"))" foot_bg_is 40 40 40
many_red() { test "$(red_cells)" -ge 100; }
until_ok 1000 many_red
check "its ANSI colour 1 is #CC241D ($(red_cells) pixels)" test "$(red_cells)" -ge 100

"$repo/bin/dots" colorscheme artboard
until_ok 1000 foot_bg_is 255 255 255
check "on Artboard the foot's background is #FFFFFF ($(pixel "$bg_x" "$bg_y"))" foot_bg_is 255 255 255
check "and no #CC241D cells are left" test "$(red_cells)" -lt 100

exit $((fails > 0))
}
