#!/usr/bin/env bash
# Frost's launcher card is glass over the paper: niri blurs only the card's rounded box with xray, so a white or a black window behind it never shows through, while the dim wash around it shows each.
{
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
far() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] >= $3 || b[i] - a[i] >= $3)) || return 1; done; }
mean_at() { grim -s 1 -t ppm -g "$1" - | mean_rgb; }

# A 40 x 40 box in the field band at the top of the card, clear of the magnifier, the caret and the Apps pill while the query is empty.
inside_geo() { launcher_state | jq -r '.cardBox | "\(.x + .w / 2 - 20 | round),\(.y + 7 | round) 40x40"'; }
# A 40 x 40 box ending 40 px left of the card, under the dim wash.
outside_geo() { launcher_state | jq -r '.cardBox | "\(.x - 80 | round),\(.y + .h / 2 - 20 | round) 40x40"'; }

foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
no_foot() { (($(foot_count) == 0)); }
# A maximised foot of one flat colour behind the launcher; the outside box reads it before the launcher opens.
behind() {
  niri msg action spawn -- foot -c /dev/null -o "colors.background=$1"
  until_ok 5000 bash -c 'niri msg -j focused-window | jq -e ".app_id == \"foot\"" >/dev/null'
  niri msg action maximize-column
}

until_ok 5000 shell_status >/dev/null
in_theme frost

open_launcher
check "frost: the card's glass fill is #d93b4252 and the cursor row's name is Inter ($(launcher_state | jq -c '[.glassFill, .nameFont]'))" state_is '.glassFill == "#d93b4252" and .nameFont == "Inter"'
check "frost: the launcher asks for one blur region, the card's box with radius 10 ($(launcher_state | jq -c '[.blurRegion, .cardBox]'))" state_is '(.blurRegion | length) == 1 and (.blurRegion[0] as $r | .cardBox as $c | ([$r.x - $c.x, $r.y - $c.y, $r.w - $c.w, $r.h - $c.h] | map(fabs < 1) | all) and $r.radius == 10)'
in_geo=$(inside_geo)
out_geo=$(outside_geo)
close_launcher

behind ffffff
white_up() { near "$(mean_at "$out_geo")" "255 255 255" 4; }
until_ok 5000 white_up
check "a maximised white foot fills $out_geo ($(mean_at "$out_geo"))" white_up
open_launcher
in_white=$(mean_at "$in_geo")
out_white=$(mean_at "$out_geo")
close_launcher
niri msg action close-window
until_ok 3000 no_foot

behind 000000
black_up() { near "$(mean_at "$out_geo")" "0 0 0" 4; }
until_ok 5000 black_up
check "a maximised black foot fills $out_geo ($(mean_at "$out_geo"))" black_up
open_launcher
in_black=$(mean_at "$in_geo")
out_black=$(mean_at "$out_geo")
close_launcher
niri msg action close-window
until_ok 3000 no_foot

check "frost: inside the glass at $in_geo reads the same over a white foot ($in_white) and a black one ($in_black), within 3" near "$in_white" "$in_black" 3
check "frost: 40 px outside the card at $out_geo the wash shows the foot, white ($out_white) and black ($out_black) apart by 40 or more" far "$out_white" "$out_black" 40

in_theme paper
open_launcher
check "paper: the launcher asks for no blur region ($(launcher_state | jq -c .blurRegion))" state_is '.blurRegion == []'
close_launcher

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0))
}
