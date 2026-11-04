#!/usr/bin/env bash
# Frost's own windows are glass: Notes and Files fill with the glass colour and ask niri to blur behind their own box, so a white or a black window behind them reads the same inside, and closing one drops the region; Paper and Artboard keep them solid and ask for none.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads" "$h/Codes" "$h/.config/gtk-3.0"
for n in IMG_2039.jpg invoice-0912.pdf notes.txt; do : >"$h/Downloads/$n"; done

status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { legacy_theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
near() { local a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"; for i in 0 1 2; do ((a[i] - b[i] <= $3 && b[i] - a[i] <= $3)) || return 1; done; }
mean_at() { grim -s 1 -t ppm -g "$1" - | mean_rgb; }

# Each window's state, how it opens and closes, and its niri window.
notes_state() { timeout 0.5 qs ipc call notes state 2>/dev/null; }
files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
state_of() { "$1_state"; }
state_is() { local w=$1; shift; state_of "$w" | jq -e "$@" >/dev/null 2>&1; }
declare -A geo in
# The window's niri record; Notes is titled Notes, Files has the app id files.
record() { niri msg -j windows | jq -c --arg w "$1" '[.[] | select(if $w == "notes" then .title == "Notes" else .app_id == "files" end)] | first // empty'; }
notes_up() { state_is notes '.open and .focused and .windowId != null'; }
files_up() { state_is files '.listed and .firstFrameMs != null' && [ -n "$(record files)" ]; }
notes_gone() { state_is notes '.open == false'; }
files_gone() { [ -z "$(record files)" ]; }
open_win() {
  case $1 in
    notes) niri msg action spawn -- dots-call notes toggle; until_ok 4000 notes_up ;;
    files) niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' DOTS_FILES_SORT=name exec dots-files >>'$work/files.log' 2>&1"; until_ok 6000 files_up
      until_ok 3000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"files\" and .is_focused)" >/dev/null' ;;
  esac
  sleep 0.5
}
close_win() { wtype -k Escape; until_ok 3000 "$1_gone"; }

# The window's box on the screen, "x,y WxH", from niri's layout.
read -r ox oy < <(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x) \(.y)"')
box_of() { record "$1" | jq -r --argjson ox "$ox" --argjson oy "$oy" '.layout | "\(($ox + .tile_pos_in_workspace_view[0] + .window_offset_in_tile[0]) | floor),\(($oy + .tile_pos_in_workspace_view[1] + .window_offset_in_tile[1]) | floor) \(.window_size[0])x\(.window_size[1])"'; }
size_of() { record "$1" | jq -c '.layout.window_size'; }
# A 40 x 40 box inside the window, 60 px in from its right edge and halfway down.
inside_geo() { record "$1" | jq -r --argjson ox "$ox" --argjson oy "$oy" '.layout | "\(($ox + .tile_pos_in_workspace_view[0] + .window_offset_in_tile[0] + .window_size[0] - 60) | floor),\(($oy + .tile_pos_in_workspace_view[1] + .window_offset_in_tile[1] + .window_size[1] / 2 - 20) | floor) 40x40"'; }
# The one region asked for is the window's own box with the 10 px corner.
region_is_window() { local s; s=$(size_of "$1"); state_is "$1" --argjson s "$s" '(.blurRegion | length) == 1 and (.blurRegion[0] as $r | $r.x == 0 and $r.y == 0 and (($r.w - $s[0]) | fabs) < 1 and (($r.h - $s[1]) | fabs) < 1 and $r.radius == 10)'; }

foot_count() { niri msg -j windows | jq '[.[] | select(.app_id == "foot")] | length'; }
no_foot() { (($(foot_count) == 0)); }
# A maximised foot of one flat colour behind the window.
behind() {
  niri msg action spawn -- foot -c /dev/null -o "colors.background=$1"
  until_ok 5000 bash -c 'niri msg -j focused-window | jq -e ".app_id == \"foot\"" >/dev/null'
  niri msg action maximize-column
}

until_ok 5000 shell_status >/dev/null
in_theme frost

for w in notes files; do
  open_win "$w"
  check "frost: $w fills with glass #d93b4252 ($(state_of "$w" | jq -c .fill))" state_is "$w" '.fill == "#d93b4252"'
  check "frost: $w asks for one blur region, its window's box with radius 10 ($(state_of "$w" | jq -c .blurRegion) in $(size_of "$w"))" region_is_window "$w"
  geo[$w]=$(inside_geo "$w")
  close_win "$w"
done

for foot in ffffff 000000; do
  behind "$foot"
  for w in notes files; do
    up() { near "$(mean_at "${geo[$w]}")" "$([ "$foot" = ffffff ] && echo 255 255 255 || echo 0 0 0)" 4; }
    until_ok 5000 up
    check "frost: a maximised $foot foot fills ${geo[$w]} with $w closed ($(mean_at "${geo[$w]}"))" up
    open_win "$w"
    in[$foot$w]=$(mean_at "${geo[$w]}")
    close_win "$w"
    until_ok 3000 up
    check "frost: after $w closes the $foot foot shows at ${geo[$w]} again ($(mean_at "${geo[$w]}"))" up
  done
  niri msg action close-window
  until_ok 3000 no_foot
done

for w in notes files; do
  check "frost: inside $w at ${geo[$w]} reads the same over a white foot (${in[ffffff$w]}) and a black one (${in[000000$w]}), within 3" near "${in[ffffff$w]}" "${in[000000$w]}" 3
done

# theme | the solid fill Qt reports for its surface
for t in "paper|#faf6ec" "artboard|#ffffff"; do
  IFS='|' read -r name solid <<<"$t"
  in_theme "$name"
  for w in notes files; do
    open_win "$w"
    check "$name: $w asks for no blur region ($(state_of "$w" | jq -c .blurRegion))" state_is "$w" '.blurRegion == []'
    check "$name: $w keeps its solid fill $solid ($(state_of "$w" | jq -c .fill))" state_is "$w" --arg f "$solid" '.fill == $f'
    close_win "$w"
  done
done

errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no QML error" test -z "$errors"

exit $((fails > 0))
}
