#!/usr/bin/env bash
# A colorscheme that does not exist is refused: dots colorscheme exits 1, Artboard stays on, and the island says why for 5 s.
{
export DOTS_DEV_SCHEME=artboard
source "$(dirname "$0")/lib.sh"
unset TMUX

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r .text; }
status_has() { shell_status | jq -e "$1" >/dev/null; }

until_ok 1000 status_has '.theme == "artboard"'
"$repo/bin/dots" colorscheme nope 2>"$DOTS_DEV_DIR/err"
code=$?
check "dots colorscheme nope exits 1 (got $code)" test "$code" = 1
check "it says why on stderr: $(<"$DOTS_DEV_DIR/err")" grep -qx 'colorscheme nope: no such colorscheme' "$DOTS_DEV_DIR/err"
check "the saved colorscheme stays artboard" test "$(<"$XDG_STATE_HOME/dots/theme")" = artboard
island_says() { [ "$(island)" = "colorscheme nope: no such colorscheme" ]; }
until_ok 1000 island_says
check "the island reads 'colorscheme nope: no such colorscheme'" island_says
check "shell status still reports artboard" status_has '.theme == "artboard"'
check "a second timer runs only while it shows" status_has '.timers == 2'
sleep 4
check "the island still says it 4 s on" island_says
until_ok 2000 eval '! island_says'
check "after 5 s the island is the clock again ($(island))" eval '! island_says'
check "and only the clock tick runs" status_has '.timers == 1'

exit $((fails > 0))
}
