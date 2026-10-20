#!/usr/bin/env bash
# A second after the shell's first frame every surface is made in the background, so even a first open is warm.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
all_loaded() { shell_status | jq -e '[.loaded[]] | sort == ["cheatsheet", "control", "goals", "launcher", "notifs", "polkit", "recorder", "themes"]' >/dev/null; }
until_ok 4000 all_loaded
check "with nothing opened, every surface has loaded ($(shell_status | jq -c .loaded))" all_loaded
one_timer() { shell_status | jq -e '.timers == 1' >/dev/null; }
until_ok 2000 one_timer
check "and warming leaves only the clock's timer running ($(shell_status | jq .timers))" one_timer

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
reported() { launcher_state | jq -e '.opens == 1 and (.openMs | type) == "number"' >/dev/null; }
niri msg action spawn -- qs ipc call launcher toggle
until_ok 3000 reported
check "the first launcher open draws within a frame of its key ($(launcher_state | jq .openMs) ms)" bash -c "(( \$(timeout 0.5 qs ipc call launcher state | jq .openMs) <= 35 ))"

exit $((fails > 0))
}
