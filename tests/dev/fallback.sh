#!/usr/bin/env bash
# A theme.toml that does not validate leaves Paper on, exits 1, and the island says why for 5 s.
source "$(dirname "$0")/lib.sh"
unset TMUX

broken=$repo/themes/broken
trap 'rm -rf "$broken"; dev_stop; rm -f "$dev_out" "$dev_log"' EXIT
mkdir -p "$broken"
grep -v '^paper = "#' "$repo/themes/paper/theme.toml" | sed 's/^name = "paper"/name = "broken"/' >"$broken/theme.toml"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .text; }
status_has() { shell_status | jq -e "$1" >/dev/null; }

"$repo/bin/dots" theme blueprint
until_ok 1000 status_has '.theme == "blueprint"'
"$repo/bin/dots" theme broken 2>"$DOTS_DEV_DIR/err"
code=$?
check "dots theme broken exits 1 (got $code)" test "$code" = 1
check "it names the file on stderr: $(<"$DOTS_DEV_DIR/err")" grep -q 'theme broken: invalid theme.toml' "$DOTS_DEV_DIR/err"
until_ok 1000 status_has '.theme == "paper"'
check "shell status falls back to paper" status_has '.theme == "paper"'
island_says() { [ "$(island)" = "theme broken: invalid theme.toml" ]; }
until_ok 1000 island_says
check "the island reads 'theme broken: invalid theme.toml'" island_says
check "a second timer runs only while it shows" status_has '.timers == 2'
sleep 4
check "the island still says it 4 s on" island_says
until_ok 2000 eval '! island_says'
check "after 5 s the island is the clock again ($(island))" eval '! island_says'
check "and only the clock tick runs" status_has '.timers == 1'

exit $((fails > 0))
