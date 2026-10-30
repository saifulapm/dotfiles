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
# A stream that plays silence until killed.
play() { pw-play -P "$1" --raw --rate 48000 --channels 2 --format s16 - </dev/zero 2>/dev/null & players+=($!); }
node_id() { pw-dump 2>/dev/null | jq -e --arg k "$1" --arg v "$2" 'first(.[] | select(.info.props[$k]? == $v) | .id)'; }
serial_of() { pw-dump 2>/dev/null | jq -e --arg n "$1" 'first(.[] | select(.info.props["node.name"]? == $n) | .info.props["object.serial"])'; }
# The sink node names the stream with $1 is linked to, one per line.
linked_to() { pw-link -l 2>/dev/null | awk -v s="$1" '/^[^ ]/ { port = $1 } $0 ~ "\\|<- " s ":" { sub(/:.*/, "", port); print port }' | sort -u; }

until_ok 5000 shell_status >/dev/null

play '{ application.name = "Test Player" }'
until_ok 3000 node_id application.name "Test Player" >/dev/null
links_null() { [ "$(linked_to pw-play)" = dots-null ]; }
until_ok 3000 links_null
check "WirePlumber links a played stream to the default sink dots-null" links_null
pw-metadata -n default "$(node_id application.name "Test Player")" target.object "$(serial_of dots-null-2)" >/dev/null
links_second() { [ "$(linked_to pw-play)" = dots-null-2 ]; }
until_ok 3000 links_second
check "a target.object write moves it to dots-null-2" links_second
one_default() { [ "$(pw-dump | jq '[.[] | select(.type == "PipeWire:Interface:Metadata" and .props["metadata.name"] == "default")] | length')" = 1 ]; }
check "there is one metadata object named default" one_default
check "the live default sink is still ${live_before#*= }" test "$(live_sink)" = "$live_before"
exit $((fails > 0))
}
