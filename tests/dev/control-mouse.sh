#!/usr/bin/env bash
# Control by mouse: a wheel notch over a level row moves it one h/l step; a click on a section tab opens it; a click on a row runs its Enter; a pointer resting on a row never moves the selection.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
section_is() { state_is --arg s "$1" '.open and .section == $s'; }
control_gone() { state_is '.open == false and .drawing == false'; }
volume_is() { [ "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" = "$1" ]; }
configured_sink() { pw-metadata -n default 0 default.configured.audio.sink 2>/dev/null | grep -q "dots-null-2\""; }
dnd_is() { [ "$(timeout 0.5 qs ipc call notifs state 2>/dev/null | jq .dnd)" = "$1" ]; }
row_of() { control_state | jq --arg t "$1" '.rows | index($t)'; }

until_ok 5000 shell_status >/dev/null
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0

niri msg action spawn -- dots-call control toggle
until_ok 3000 state_is '.open and .settled and .section == "audio" and .keyboard'
until_ok 3000 state_is '.rows | index("Dots second sink") != null'

sink=$(row_of "Dots null sink")
wheel_box "control-row:$sink" -1
until_ok 2000 volume_is "Volume: 0.45"
check "one wheel notch up over the default sink's row reads 45 % ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is "Volume: 0.45"
wheel_box "control-row:$sink" 1
until_ok 2000 volume_is "Volume: 0.40"
check "and one notch down reads 40 % again ($(wpctl get-volume @DEFAULT_AUDIO_SINK@))" volume_is "Volume: 0.40"

second=$(row_of "Dots second sink")
click_box "control-row:$second"
until_ok 2000 configured_sink
check "a click on the second sink's row makes it the configured default, as Enter does" configured_sink
check "and selects that row ($(control_state | jq -c '{selected}'))" state_is --argjson i "$second" '.selected == $i'

click_box control-tab:route
until_ok 2000 section_is route
check "a click on the Route tab opens Route" section_is route
until_ok 2000 state_is '.rows | index("Do Not Disturb") != null'
before=$(timeout 0.5 qs ipc call notifs state | jq .dnd)
after=$([ "$before" = true ] && echo false || echo true)
dndrow=$(row_of "Do Not Disturb")
click_box "control-row:$dndrow"
until_ok 2000 dnd_is "$after"
check "a click on the Do Not Disturb row flips it as Enter does ($before to $after)" dnd_is "$after"
click_box "control-row:$dndrow"
until_ok 2000 dnd_is "$before"
check "and a second click flips it back" dnd_is "$before"

click_box control-tab:audio
until_ok 2000 section_is audio
until_ok 2000 state_is '.keyboard'
for n in 1 2 3 4 5 6 7 8; do wtype k; done
until_ok 2000 state_is '.selected == 0'
point move $(shell_spot control-row:2)
wtype j
until_ok 2000 state_is '.selected == 1'
sleep 0.3
check "with the pointer resting on row 2, j moves the selection to row 1 only ($(control_state | jq -c '{selected}'))" state_is '.selected == 1'
wtype k
until_ok 2000 state_is '.selected == 0'
sleep 0.3
check "and k back to row 0 ($(control_state | jq -c '{selected}'))" state_is '.selected == 0'

timeout 0.5 qs ipc call control close
until_ok 2000 control_gone
exit "$fails"
}
