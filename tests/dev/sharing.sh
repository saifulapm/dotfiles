#!/usr/bin/env bash
# Any niri cast but the shell's own recording puts LIVE on the island: over REC, under a notification's 5 s, and through Do Not Disturb.
{
# The shell records with wf-recorder -D, which niri reports as no cast, so the relay stands in for niri reporting one with the recorder's pid.
export DOTS_DEV_FAKE_CASTS=1
source "$(dirname "$0")/lib.sh"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_text() { island | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null; }
reads_rec() { [[ $(island_text) =~ ^REC\ [0-9]{2}:[0-9]{2}$ ]]; }
casts() { niri msg -j casts | jq length; }
casts_are() { [ "$(casts)" = "$1" ]; }
rec_state() { timeout 0.5 qs ipc call record state 2>/dev/null; }
rec_is() { rec_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
record_full() {
  niri msg action spawn -- dots-call record toggle
  until_ok 3000 rec_is '.picking'
  wtype f
  until_ok 2000 rec_is '.region.x == 0 and .region.y == 0'
  wtype -k Return
  until_ok 3000 rec_is '.recording'
}
record_stop() { niri msg action spawn -- dots-call record toggle; until_ok 6000 rec_is '.recording | not'; }
# Samples the island every 100 ms for $1 s and prints each text it read, once each.
texts_for() { for _ in $(seq $(($1 * 10))); do island_text; sleep 0.1; done | sed -E 's/^REC [0-9]{2}:[0-9]{2}$/REC mm:ss/' | sort -u | paste -sd'|'; }
wf=
share() { wf-recorder -y -f "$DOTS_DEV_DIR/share-$1.mp4" >/dev/null 2>&1 & wf=$!; }
unshare() { kill -INT "$wf"; wait "$wf" 2>/dev/null || true; wf=; }
cleanup() { [ -z "$wf" ] || unshare; }

until_ok 2000 mode_is rest
check "at rest the island is the clock" mode_is rest

t0=$(now_ms)
share 1
until_ok 3000 reads "LIVE SCREEN"
ms=$(($(now_ms) - t0))
check "a wf-recorder started outside the shell reads LIVE SCREEN, ${ms} ms after it started" reads "LIVE SCREEN"
check "within 1 s" test "$ms" -le 1000
unshare
until_ok 2000 mode_is rest
check "stopping it takes LIVE away" mode_is rest

record_full
until_ok 2000 reads_rec
seen=$(texts_for 3)
check "the shell's own recording reads REC and never LIVE ($seen)" test "$seen" = "REC mm:ss"
pid=$(rec_state | jq .pid)
is_wf() { [ "$(cat "/proc/$1/comm" 2>/dev/null)" = wf-recorder ]; }
check "the recorder knows its wf-recorder's pid ($pid)" is_wf "$pid"
own() { fake_event "{\"CastStartedOrChanged\":{\"cast\":{\"stream_id\":900,\"session_id\":900,\"kind\":\"WlrScreencopy\",\"target\":{\"Output\":{\"name\":\"winit\"}},\"is_dynamic_target\":false,\"is_active\":true,\"pid\":$1,\"pw_node_id\":null}}}" >/dev/null; }
own "$pid"
seen=$(texts_for 2)
check "a cast niri reports with the recorder's pid still reads REC, never LIVE ($seen)" test "$seen" = "REC mm:ss"
own $((pid + 1))
until_ok 2000 reads "LIVE SCREEN"
check "and one with any other pid reads LIVE SCREEN" reads "LIVE SCREEN"
fake_event '{"CastStopped":{"stream_id":900}}' >/dev/null
until_ok 2000 reads_rec

share 2
until_ok 3000 reads "LIVE SCREEN"
check "a share during the shell's recording reads LIVE SCREEN, not REC or ×2" reads "LIVE SCREEN"
unshare
until_ok 2000 reads_rec
check "once the share stops, REC comes back ($(island_text), $(niri msg -j casts | jq -c 'map(.pid)'))" reads_rec
record_stop
# The recording's Recording saved notification outranks LIVE for its 5 s.
until_ok 8000 mode_is rest

timeout 0.5 qs ipc call notifs dnd true
dnd_on() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e '.dnd == true' >/dev/null; }
until_ok 2000 dnd_on
check "Do Not Disturb is on" dnd_on
share 3
until_ok 3000 reads "LIVE SCREEN"
check "with Do Not Disturb on, a share still reads LIVE SCREEN" reads "LIVE SCREEN"
timeout 0.5 qs ipc call notifs dnd false

notify-send hi
until_ok 2000 mode_is notification
check "a notification shows over LIVE" mode_is notification
t0=$(now_ms)
until_ok 8000 reads "LIVE SCREEN"
ms=$(($(now_ms) - t0))
check "and LIVE SCREEN comes back ${ms} ms later, after the notification's 5 s" test "$ms" -ge 4000 -a "$ms" -le 6500

# A share running before the shell starts is in the stream's first burst.
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
until_ok 3000 reads "LIVE SCREEN"
check "a shell started during a share reads LIVE SCREEN" reads "LIVE SCREEN"
unshare
until_ok 2000 mode_is rest

# A restart ends the shell's own wf-recorder with it, so nothing of that recording is left to read as LIVE.
record_full
pid=$(rec_state | jq .pid)
systemctl --user restart "$DOTS_DEV_UNIT"
until_ok 10000 shell_status >/dev/null
until_ok 3000 casts_are 0
seen=$(texts_for 2)
check "a restart mid-recording ends the shell's wf-recorder ($pid)" bash -c '! kill -0 "$1" 2>/dev/null' _ "$pid"
check "and niri lists no cast ($(niri msg -j casts | jq -c 'map(.pid)'))" casts_are 0
check "and the island reads neither LIVE nor REC ($seen)" bash -c '! grep -qE "LIVE|REC" <<<"$1"' _ "$seen"

exit $((fails > 0))
}
