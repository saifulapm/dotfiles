#!/usr/bin/env bash
# The island's mic slot: an app recording from the default source reads ● MIC · <app>, under the nested WirePlumber, whatever Do Not Disturb, a lease or a recording says.
{
export DOTS_DEV_WIREPLUMBER=1
export DOTS_DEV_FAKE_CASTS=1
source "$(dirname "$0")/lib.sh"

under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${PIPEWIRE_RUNTIME_DIR:-}" || { echo "FAIL PIPEWIRE_RUNTIME_DIR is not the nested one"; exit 1; }

recs=()
cleanup() {
  [ ${#recs[@]} -eq 0 ] || kill "${recs[@]}" 2>/dev/null
  timeout 0.5 qs ipc call notifs dnd false >/dev/null 2>&1
}
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_text() { island | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }
not_mode() { ! mode_is "$1"; }
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
# A capture stream from the default source that records silence until killed; its pid is the last in recs.
record() { pw-record -P "$1" --raw - >/dev/null 2>&1 & recs+=($!); }
node_id() { pw-dump 2>/dev/null | jq -e --arg k "$1" --arg v "$2" 'first(.[] | select(.info.props[$k]? == $v) | .id)'; }
# The capture node names linked from the source named $1, one per line.
linked_from() { pw-link -l 2>/dev/null | awk -v s="$1" '/^[^ ]/ { port = $1 } $0 ~ "\\|-> " { sub(/^ *\|-> /, ""); if (port ~ "^" s ":") { sub(/:.*/, ""); print } }' | sort -u; }
links_into() { linked_from dots-mic | grep -qxF "$1"; }
# The mic slot never shows over $1 ms.
never_mic() {
  local end=$(($(now_ms) + $1))
  while (($(now_ms) < end)); do
    mode_is mic && return 1
    sleep 0.05
  done
}
one_timer() { shell_status | jq -e '.timers == 1' >/dev/null; }

until_ok 5000 shell_status >/dev/null
until_ok 2000 mode_is rest
default_source=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | sed -n 's/.*node\.name = "\(.*\)"/\1/p' | head -1)
check "the nested default source is dots-mic ($default_source)" test "$default_source" = dots-mic

record '{ application.name = "Test Recorder" node.name = test-recorder }'
until_ok 3000 links_into test-recorder
check "WirePlumber links Test Recorder from dots-mic" links_into test-recorder
until_ok 2000 reads "● MIC · Test Recorder"
check "an app recording from the default source reads ● MIC · Test Recorder ($(island_text))" reads "● MIC · Test Recorder"
check "shell status reads 1 timer while the mic slot shows" one_timer

record '{ application.name = "Other" node.name = test-other }'
other=${recs[-1]}
until_ok 3000 reads "● MIC · Other +1"
check "a newer second app reads ● MIC · Other +1 ($(island_text))" reads "● MIC · Other +1"
kill "$other"
until_ok 2000 reads "● MIC · Test Recorder"

# Do Not Disturb hides notifications, never the mic.
timeout 0.5 qs ipc call notifs dnd true >/dev/null
dnd_on() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e '.dnd == true' >/dev/null; }
until_ok 2000 dnd_on
notify-send hidden
sleep 0.3
check "with Do Not Disturb on the mic slot still shows" reads "● MIC · Test Recorder"
timeout 0.5 qs ipc call notifs dnd false >/dev/null

# A share outranks the mic slot, which comes back when it ends.
fake_event '{"CastStartedOrChanged":{"cast":{"stream_id":1001,"session_id":1001,"kind":"PipeWire","target":{"Output":{"name":"winit"}},"is_dynamic_target":true,"is_active":true,"pid":null,"pw_node_id":1041}}}' >/dev/null
until_ok 2000 mode_is sharing
check "with a share running the island reads LIVE ($(island_text))" mode_is sharing
fake_event '{"CastStopped":{"stream_id":1001}}' >/dev/null
until_ok 2000 reads "● MIC · Test Recorder"

# An agent's lease gives way to the mic slot.
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
# An agent unlock turns the monitors off a second later, so the check wakes them as lease-island.sh does.
off=$(timeout 0.5 qs ipc call lock state | jq .monitorsOff)
timeout 0.5 qs ipc call lock unlock claude 5 >/dev/null
until_ok 3000 lock_is ".locked == false and .heldBy == \"claude\" and .monitorsOff > $off"
niri msg action power-on-monitors
check "with a lease the island shows the mic slot ($(island_text))" reads "● MIC · Test Recorder"

# The slot goes within a second of the stream ending.
first=${recs[0]}
kill "$first"
t0=$(now_ms)
until_ok 3000 not_mode mic
took=$(($(now_ms) - t0))
check "the stream ending removes the slot within 1 s (${took} ms)" test "$took" -le 1000
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
wtype dots-test-pass
wtype -k Return
until_ok 3000 lock_is '.locked == false and .heldBy == ""'
until_ok 3000 mode_is rest

# A monitor stream is linked from the mic as an app's is, and still shows nothing.
record '{ application.name = "Peak Meter" node.name = test-peak stream.monitor = true }'
until_ok 3000 links_into test-peak
check "WirePlumber links the monitor stream from dots-mic" links_into test-peak
check "a stream.monitor stream alone shows no mic slot" never_mic 1500
kill "${recs[-1]}"

# The shell's own recorder: its pid's stream is the timer's, not the mic slot's.
rec_state() { timeout 0.5 qs ipc call record state 2>/dev/null; }
rec_is() { rec_state | jq -e "$1" >/dev/null; }
niri msg action spawn -- dots-call record toggle
until_ok 3000 rec_is '.picking'
wtype f
wtype -k Return
until_ok 3000 rec_is '.recording and .pid > 0'
pid=$(rec_state | jq .pid)
record "{ application.name = \"wf-recorder\" node.name = test-own application.process.id = $pid }"
until_ok 3000 links_into test-own
own_pid() { [ "$(pw-dump 2>/dev/null | jq -r 'first(.[] | select(.info.props["node.name"]? == "test-own") | .info.props["application.process.id"])')" = "$pid" ]; }
check "the recorder's stream carries the recorder's pid $pid" own_pid
recs_timer() { [[ $(island_text) =~ ^REC\ 00:0[0-9]$ ]]; }
until_ok 2000 recs_timer
check "the shell's own recording with the mic reads REC 00:0x and no MIC ($(island_text))" never_mic 1500
check "and the island reads REC 00:0x" recs_timer
kill "${recs[-1]}"
niri msg action spawn -- dots-call record toggle
until_ok 5000 rec_is '.recording | not'
until_ok 8000 mode_is rest

# A target node destroyed under its link: the slot goes, and the shell still answers.
for n in 1 2 3; do
  record "{ application.name = \"Gone $n\" node.name = test-gone-$n }"
  until_ok 2000 reads "● MIC · Gone $n"
  pw-cli destroy "$(node_id node.name "test-gone-$n")" >/dev/null 2>&1
  until_ok 3000 not_mode mic
done
check "a destroyed target leaves no mic slot ($(island | jq -c '{mode, text}'))" never_mic 1000
check "and shell status still answers" shell_status
exit $((fails > 0))
}
