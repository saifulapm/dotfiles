#!/usr/bin/env bash
# At the live speed the Recorder's picker, the one surface still drawn outside the island, opens on the one spring (240 ms) and settles in 220 to 280 ms, no sooner than a frame or so short of it.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

surface_is() { timeout 0.5 qs ipc call "$1" state 2>/dev/null | jq -e "$2" >/dev/null; }
springs='.motion == "spring" and (.settleMs | type) == "number" and .settleMs >= 220 and .settleMs <= 280'

until_ok 5000 shell_status >/dev/null
# Every other surface grows from the island on its own motion, which island-motion.sh times.

# The recorder's picker opens and closes on its one toggle.
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 3000 surface_is record .settled
check "the recorder's picker settles as a spring in 220 to 280 ms ($(timeout 0.5 qs ipc call record state | jq -c '[.motion, .settleMs]'))" surface_is record ".picking and $springs"
niri msg action spawn -- dots-call record toggle >/dev/null
until_ok 2000 surface_is record '.drawing == false'

exit $((fails > 0))
}
