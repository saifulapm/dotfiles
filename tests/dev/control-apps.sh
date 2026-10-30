#!/usr/bin/env bash
# Control Audio's app rows: a playing stream gets a row after the outputs, which h, l, m and Enter act on, under the nested WirePlumber.
{
export DOTS_DEV_WIREPLUMBER=1
source "$(dirname "$0")/lib.sh"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }
live_sink() { env -u PIPEWIRE_RUNTIME_DIR wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m1 'node.name'; }
live_before=$(live_sink)

players=()
cleanup() { [ ${#players[@]} -eq 0 ] || kill "${players[@]}" 2>/dev/null; }
control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
# The detail drawn on the row titled $1.
detail_of() { control_state | jq -r --arg t "$1" '(.rows | index($t)) as $i | if $i == null then empty else .detailsDrawn[$i] end'; }
# Presses j or k until the row titled $1 is selected.
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
# A stream that plays silence until killed.
play() { pw-play -P "$1" --raw --rate 48000 --channels 2 --format s16 - </dev/zero 2>/dev/null & players+=($!); }
node_id() { pw-dump 2>/dev/null | jq -e --arg k "$1" --arg v "$2" 'first(.[] | select(.info.props[$k]? == $v) | .id)'; }
serial_of() { pw-dump 2>/dev/null | jq -e --arg n "$1" 'first(.[] | select(.info.props["node.name"]? == $n) | .info.props["object.serial"])'; }
# The sink node names the stream with $1 is linked to, one per line.
linked_to() { pw-link -l 2>/dev/null | awk -v s="$1" '/^[^ ]/ { port = $1 } $0 ~ "\\|<- " s ":" { sub(/:.*/, "", port); print port }' | sort -u; }

until_ok 5000 shell_status >/dev/null

play '{ application.name = "Test Player" node.name = test-player }'
until_ok 3000 node_id application.name "Test Player" >/dev/null
links_null() { [ "$(linked_to test-player)" = dots-null ]; }
until_ok 3000 links_null
check "WirePlumber links a played stream to the default sink dots-null" links_null
pw-metadata -n default "$(node_id application.name "Test Player")" target.object "$(serial_of dots-null-2)" >/dev/null
links_second() { [ "$(linked_to test-player)" = dots-null-2 ]; }
until_ok 3000 links_second
check "a target.object write moves it to dots-null-2" links_second
one_default() { [ "$(pw-dump | jq '[.[] | select(.type == "PipeWire:Interface:Metadata" and .props["metadata.name"] == "default")] | length')" = 1 ]; }
check "there is one metadata object named default" one_default
pw-metadata -n default "$(node_id application.name "Test Player")" target.object "$(serial_of dots-null)" >/dev/null
until_ok 3000 links_null

# A stream with no application name, and a capture stream linked to a sink's monitor, which gets no row.
pw-cli create-node adapter '{ factory.name = support.null-audio-sink node.name = bare-stream node.description = "Bare stream" media.class = Stream/Output/Audio audio.position = [ FL FR ] node.autoconnect = true object.linger = true }' >/dev/null
pw-record --target dots-null -P '{ application.name = "Test Recorder" stream.capture.sink = true }' --raw - >/dev/null 2>&1 &
players+=($!)
until_ok 3000 node_id node.name bare-stream >/dev/null
until_ok 3000 node_id application.name "Test Recorder" >/dev/null

volume_of() { [ "$(wpctl get-volume "$1")" = "$2" ]; }
player=$(node_id application.name "Test Player")
wpctl set-volume "$player" 0.40
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40
until_ok 2000 volume_of "$player" "Volume: 0.40"

niri msg action spawn -- dots-call control toggle
until_ok 3000 state_is '.open and .section == "audio" and .keyboard'
# Rows of a kind keep PipeWire's order, so each kind is read as a set.
rows_are() { state_is --argjson a "$1" '(.rows[0:2] | sort) == ["Dots null sink","Dots second sink"] and (.rows[2:-1] | sort) == $a and .rows[-1] == "Dots null source"'; }
until_ok 3000 rows_are '["Bare stream","Test Player"]'
check "the playing apps sit after the outputs, and the capture stream has no row" rows_are '["Bare stream","Test Player"]'
detail_is() { [ "$(detail_of "$1")" = "$2" ]; }
until_ok 2000 detail_is "Test Player" "Dots null sink · 40%"
check "Test Player's detail names its output and volume" detail_is "Test Player" "Dots null sink · 40%"
detail_is "Test Player" "Dots null sink · 40%" || echo "     detail: $(detail_of "Test Player"), $(wpctl get-volume "$player")"
check "a stream with no application name is titled by its node description" detail_is "Bare stream" "Dots null sink · 100%"

until_ok 3000 select_row "Test Player"
wtype h
until_ok 2000 volume_of "$player" "Volume: 0.35"
check "h on Test Player lowers its volume from 0.40 to 0.35" volume_of "$player" "Volume: 0.35"
check "and leaves Dots null sink at 0.40" volume_of @DEFAULT_AUDIO_SINK@ "Volume: 0.40"
until_ok 2000 detail_is "Test Player" "Dots null sink · 35%"
check "the detail reads 35%" detail_is "Test Player" "Dots null sink · 35%"
wtype m
until_ok 2000 volume_of "$player" "Volume: 0.35 [MUTED]"
check "m mutes the stream" volume_of "$player" "Volume: 0.35 [MUTED]"
until_ok 2000 detail_is "Test Player" "Dots null sink · muted"
check "its detail reads muted" detail_is "Test Player" "Dots null sink · muted"
check "the sink stays unmuted" volume_of @DEFAULT_AUDIO_SINK@ "Volume: 0.40"
wtype m
until_ok 2000 volume_of "$player" "Volume: 0.35"
check "m again unmutes it" volume_of "$player" "Volume: 0.35"

# Two sinks, so one Enter moves on from the first and the other wraps from the last, whichever order PipeWire lists them in.
target_is() { pw-metadata -n default "$player" target.object 2>/dev/null | grep -q "value:'$1'"; }
wtype -k Return
until_ok 3000 target_is "$(serial_of dots-null-2)"
check "Enter sets Test Player's target.object to Dots second sink's serial" target_is "$(serial_of dots-null-2)"
until_ok 3000 links_second
check "the stream links to Dots second sink" links_second
until_ok 2000 detail_is "Test Player" "Dots second sink · 35%"
check "the detail names Dots second sink" detail_is "Test Player" "Dots second sink · 35%"
wtype -k Return
until_ok 3000 links_null
check "Enter again moves it back to Dots null sink" links_null
until_ok 2000 detail_is "Test Player" "Dots null sink · 35%"
check "the detail names Dots null sink" detail_is "Test Player" "Dots null sink · 35%"

until_ok 3000 select_row "Bare stream"
pw-cli destroy "$(node_id node.name bare-stream)" >/dev/null
until_ok 3000 rows_are '["Test Player"]'
check "the stream ending removes its row" rows_are '["Test Player"]'
check "the selection stays on a row that exists" state_is '.selected < (.rows | length)'
timeout 0.5 qs ipc call control close
check "the live default sink is still ${live_before#*= }" test "$(live_sink)" = "$live_before"
exit $((fails > 0))
}
