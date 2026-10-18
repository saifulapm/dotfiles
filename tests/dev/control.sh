#!/usr/bin/env bash
# Mod+C opens Control on Audio; Tab moves between sections; h/l, m and Enter act on the nested PipeWire's nodes.
source "$(dirname "$0")/lib.sh"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }
live_volume() { env -u PIPEWIRE_RUNTIME_DIR wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; }
live_before=$(live_volume)

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_c() { niri msg action spawn -- qs ipc call control toggle; }
control_focus() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .layer == "Overlay" and .keyboard_interactivity == $k)' >/dev/null; }
# The Audio tab's left padding, left of its text, drawn in ink only while Control shows on audio.
tab_rgb() {
  local geo
  geo=$(niri msg -j outputs | jq -r 'first(.[]).logical | "\(.x + (.width / 2 | floor) - 339),\(.y + 186) 5x16"')
  grim -s 1 -t ppm -g "$geo" - | mean_rgb
}
tab_is_ink() { local r g b; read -r r g b < <(tab_rgb); ((r < 60 && g < 60 && b < 60)); }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
volume_is() { [ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "$1" ]; }
# Presses j until the row titled $1 is selected.
select_row() {
  local i n
  i=$(control_state | jq --arg t "$1" '.rows | index($t)')
  [ -n "$i" ] && [ "$i" != null ] || return 1
  for n in 1 2 3 4 5 6 7 8; do
    state_is --argjson i "$i" '.selected == $i' && return 0
    if state_is --argjson i "$i" '.selected < $i'; then wtype j; else wtype k; fi
    sleep 0.1
  done
  return 1
}
configured_sink() { pw-metadata -n default 0 default.configured.audio.sink 2>/dev/null | grep -q "dots-null-2\""; }

until_ok 5000 shell_status >/dev/null
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0

mod_c
control_shown() { section_is audio && control_focus Exclusive && tab_is_ink; }
until_ok 3000 control_shown
check "Mod+C shows Control on audio with exclusive keyboard" control_shown
check "state lists the six sections in order" state_is '.sections == ["audio","wifi","bluetooth","power","display","route"]'
until_ok 3000 state_is '(.openMs | type) == "number" and .opens == 1'
check "the open reports a numeric openMs" state_is '(.openMs | type) == "number"'

wtype -k Tab
wtype -k Tab
until_ok 2000 section_is bluetooth
check "Tab twice is bluetooth" section_is bluetooth
wtype -M shift -k Tab -m shift
until_ok 2000 section_is wifi
check "Shift+Tab once is wifi" section_is wifi
wtype -M shift -k Tab -m shift
until_ok 2000 section_is audio

until_ok 3000 state_is '.rows | index("Dots second sink") != null'
check "Audio lists both sinks and the source" state_is '.rows | (index("Dots null sink") != null and index("Dots second sink") != null and index("Dots null source") != null)'
until_ok 3000 select_row "Dots null sink"
wtype l
until_ok 2000 volume_is "Volume: 0.45"
check "l raises the default sink from 0.40 to 0.45" volume_is "Volume: 0.45"
wtype m
until_ok 2000 volume_is "Volume: 0.45 [MUTED]"
check "m mutes it" volume_is "Volume: 0.45 [MUTED]"
wtype m
until_ok 2000 volume_is "Volume: 0.45"
check "m again unmutes it" volume_is "Volume: 0.45"

until_ok 3000 select_row "Dots second sink"
wtype -k Return
until_ok 2000 configured_sink
check "Enter on the second sink makes it the configured default" configured_sink
until_ok 2000 state_is '.defaultSink == "dots-null-2"'
check "state reports dots-null-2 as the default sink" state_is '.defaultSink == "dots-null-2"'
echo "     state: $(control_state)"

wtype -k Escape
control_gone() { state_is '.open == false' && control_focus None && ! tab_is_ink; }
until_ok 2000 control_gone
check "Esc closes Control and releases the keyboard" control_gone

check "the live volume is still ${live_before#Volume: }" test "$(live_volume)" = "$live_before"
exit $((fails > 0))
