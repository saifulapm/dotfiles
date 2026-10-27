#!/usr/bin/env bash
# niri drops an event stream that falls 64 events behind; the shell connects again and still reads a running share as LIVE.
{
source "$(dirname "$0")/lib.sh"

island_text() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .text; }
reads() { [ "$(island_text)" = "$1" ]; }
dropped() { grep -q "reading events too slowly" "$dev_log"; }
wf=
cleanup() { [ -z "$wf" ] || { kill -INT "$wf"; wait "$wf" 2>/dev/null || true; }; }

# A window gives each workspace switch events to send.
niri msg action spawn -- foot -c /dev/null
foot_open() { niri msg -j windows | jq -e 'any(.[]; .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_open

wf-recorder -y -f "$DOTS_DEV_DIR/share.mp4" >/dev/null 2>&1 &
wf=$!
until_ok 3000 reads "LIVE SCREEN"
check "a wf-recorder share reads LIVE SCREEN" reads "LIVE SCREEN"

# A frozen shell reads nothing, so each workspace switch's small events fill its socket and then niri's queue.
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
kill -STOP "$pid"
for _ in $(seq 400); do
  niri msg action focus-workspace-down
  niri msg action focus-workspace-up
  dropped && break
done
kill -CONT "$pid"
check "niri dropped the frozen shell's event stream" dropped

until_ok 3000 reads "LIVE SCREEN"
check "after the drop, the share still reads LIVE SCREEN" reads "LIVE SCREEN"
kill -INT "$wf"
wait "$wf" 2>/dev/null
wf=
until_ok 2000 bash -c '! timeout 0.5 qs ipc call island state | jq -e ".mode == \"sharing\"" >/dev/null'
check "and stopping it after the drop takes LIVE away" bash -c '! timeout 0.5 qs ipc call island state | jq -e ".mode == \"sharing\"" >/dev/null'

exit $((fails > 0))
}
