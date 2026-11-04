#!/usr/bin/env bash
# Frost's island is glass: its window asks niri to blur its own rounded box, apart from any panel open in the Surfaces window, so a white or a black window behind the card reads the same inside it; Artboard asks for none.
{
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$1" >/dev/null 2>&1; }
control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
control_is() { control_state | jq -e "$1" >/dev/null 2>&1; }
blur_is() { timeout 0.5 qs ipc call shell blur 2>/dev/null | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { legacy_theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
open_control() { niri msg action spawn -- dots-call control toggle; until_ok 3000 control_is '.open and .keyboard and .settled'; }
close_control() { wtype -k Escape; until_ok 2000 control_is '.open == false and .drawing == false'; }
# A notification three lines deep, once its morph has settled; the island holds it 5 s.
notify() { notify-send -a Chromium "$1" $'report-october.pdf\n2.4 MB\nDownloads'; until_ok 3000 island_is ".mode == \"notification\" and .animating == false and .note.summary == \"$1\""; }
at_rest() { until_ok 7000 island_is '.mode == "rest" and .animating == false'; }
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
mean_at() { grim -s 1 -t ppm -g "$1" - | mean_rgb; }

# The island window is 560 + 2 x 32 px wide, centred on the output, so a box in its pixels sits this far left of the same box on the output.
out_w=$(niri msg -j outputs | jq -r 'first(.[]).logical.width')
offset=$(((out_w - 624) / 2))
# The region asked for is the island's box with the theme's 10 px corner, moved into output pixels.
region_is_box="(.note.blurRegion | length) == 1 and (.note.blurRegion[0] as \$r | .note.islandBox as \$b | ([\$r.x + $offset - \$b.x, \$r.y - \$b.y, \$r.w - \$b.w, \$r.h - \$b.h] | map(fabs < 1) | all) and \$r.radius == 10)"
region_is_card='(.blurRegion | length) == 1 and (.blurRegion[0] as $r | .cardBox as $c | ([$r.x - $c.x, $r.y - $c.y, $r.w - $c.w, $r.h - $c.h] | map(fabs < 1) | all) and $r.radius == 10)'

foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
no_foot() { (($(foot_count) == 0)); }
# A maximised foot of one flat colour behind the island.
behind() {
  niri msg action spawn -- foot -c /dev/null -o "colors.background=$1"
  until_ok 5000 bash -c 'niri msg -j focused-window | jq -e ".app_id == \"foot\"" >/dev/null'
  niri msg action maximize-column
}

until_ok 5000 shell_status >/dev/null
in_theme frost

notify "Download complete"
echo "     note: $(island | jq -c '.note | {blurRegion, islandBox}') offset $offset"
check "frost: the island asks for one blur region, its box with radius 10" island_is "$region_is_box"
# 40 x 40 inside the card at its right, clear of the clock pill at rest and low enough to sit over a maximised window.
in_geo=$(island | jq -r '.note.islandBox | "\(.x + .w - 60 | round),\(.y + .h - 50 | round) 40x40"')
at_rest

open_control
notify "Both open"
both=$(island | jq -c '.note | {blurRegion, islandBox}')
echo "     island: $both control: $(control_state | jq -c '{blurRegion, cardBox}')"
check "frost: with Control open the island still asks for its own box" island_is "$region_is_box"
check "frost: Control asks for its own card's box" control_is "$region_is_card"
check "frost: the Surfaces window asks niri for the one region of Control" blur_is '.surfaces == 1'
island_box=$(jq -c .islandBox <<<"$both")
check "frost: the two regions are separate boxes ($island_box and $(control_state | jq -c .cardBox))" control_is "(.cardBox as \$c | $island_box as \$i | \$c.y >= \$i.y + \$i.h or \$i.y >= \$c.y + \$c.h or \$c.x >= \$i.x + \$i.w or \$i.x >= \$c.x + \$c.w)"
close_control
at_rest

behind ffffff
# At rest the island is the narrow clock pill, so the white foot shows where the card was: no blurred box is left there.
white_up() { near "$(mean_at "$in_geo")" "255 255 255" 4; }
until_ok 5000 white_up
check "frost: a maximised white foot fills $in_geo with the island at rest ($(mean_at "$in_geo"))" white_up
notify "Over white"
in_white=$(mean_at "$in_geo")
at_rest
niri msg action close-window
until_ok 3000 no_foot

behind 000000
black_up() { near "$(mean_at "$in_geo")" "0 0 0" 4; }
until_ok 5000 black_up
check "frost: a maximised black foot fills $in_geo with the island at rest ($(mean_at "$in_geo"))" black_up
notify "Over black"
in_black=$(mean_at "$in_geo")
at_rest
niri msg action close-window
until_ok 3000 no_foot

check "frost: inside the island card at $in_geo reads the same over a white foot ($in_white) and a black one ($in_black), within 3" near "$in_white" "$in_black" 3

in_theme artboard
notify "Download complete"
check "artboard: the island asks for no blur region ($(island | jq -c .note.blurRegion))" island_is '.note.blurRegion == []'

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0))
}
