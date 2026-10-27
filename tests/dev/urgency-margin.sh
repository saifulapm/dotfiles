#!/usr/bin/env bash
# The top-left margin marks each workspace holding a foot that rang BEL with bell.urgent, the current one too, at most 3 then +N.
{
source "$(dirname "$0")/lib.sh"

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
marks_are() { margins | jq -e --arg want "$1" '.drawn.marks == $want' >/dev/null 2>&1; }
win_id() { niri msg -j windows | jq -r --arg t "$1" '.[] | select(.title == $t) | .id'; }
focused_is() { niri msg -j focused-window | jq -e --arg t "$1" '.title == $t' >/dev/null 2>&1; }
# Each urgent foot waits for its own file, so it rings only once the check has looked away from it.
bells="$DOTS_DEV_DIR/bells"
mkdir -p "$bells"
ringer() { niri msg action spawn -- foot -c /dev/null -o bell.urgent=yes -T "$1" sh -c "until [ -e '$bells/$1' ]; do sleep 0.05; done; printf '\a'; sleep 600"; until_ok 5000 focused_is "$1"; }
ring() { touch "$bells/$1"; }
plain() { niri msg action spawn -- foot -c /dev/null -T "$1" sleep 600; until_ok 5000 focused_is "$1"; }

until_ok 5000 shell_status >/dev/null
# niri drops an empty workspace once focus leaves it, so workspace 1 keeps a window of its own.
plain one
niri msg action focus-workspace 2
ringer two
niri msg action focus-workspace 1
until_ok 2000 focused_is one
ring two
until_ok 2000 marks_are "!02"
echo "     drawn: $(margins | jq -c .drawn)"
check "a foot ringing on workspace 2 marks !02 while workspace 1 is shown" marks_are "!02"

# A mark that never came cannot go, so each check of a mark going reads it there first.
had=$(margins | jq -r .drawn.marks)
niri msg action focus-window --id "$(win_id two)"
start=$(now_ms)
until_ok 2000 marks_are ""
elapsed=$(($(now_ms) - start))
check "focusing the urgent foot clears its mark $had in ${elapsed} ms" eval '[ "$had" = "!02" ] && marks_are "" && [ "$elapsed" -le 1000 ]'

niri msg action focus-workspace 1
ringer here
niri msg action focus-window --id "$(win_id one)"
until_ok 2000 focused_is one
ring here
until_ok 2000 marks_are "!01"
check "an urgent foot on the current workspace 1 marks !01" marks_are "!01"
had=$(margins | jq -r .drawn.marks)
niri msg action close-window --id "$(win_id here)"
until_ok 2000 marks_are ""
check "closing the urgent foot unfocused takes its mark $had away" eval '[ "$had" = "!01" ] && marks_are ""'

# Workspaces 4 and 6 hold a quiet foot each, so 5 and 7 keep their numbers.
for n in 3 4 5 6 7; do
  niri msg action focus-workspace "$n"
  case $n in 4 | 6) plain "quiet$n" ;; *) ringer "ws$n" ;; esac
done
niri msg action focus-workspace 2
ringer ws2
niri msg action focus-workspace 1
until_ok 2000 focused_is one
for n in 2 3 5 7; do ring "ws$n"; done
until_ok 3000 marks_are "!02 !03 !05 +1"
echo "     drawn: $(margins | jq -c .drawn)"
check "urgent windows on workspaces 2, 3, 5 and 7 mark !02 !03 !05 +1" marks_are "!02 !03 !05 +1"
check "the marks are danger red" eval 'margins | jq -e ".drawn.markColors | unique == [\"#c8381e\"]" >/dev/null'

# An agent's lease brings the screen back with the marks still drawn.
lock_is() { timeout 0.5 qs ipc call lock state 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
niri msg action spawn -- dots-call lock lock
until_ok 3000 lock_is '.locked and .secure'
timeout 0.5 qs ipc call lock unlock claude 2 >/dev/null
until_ok 3000 lock_is '.locked == false'
check "under an agent's lease the margin still marks !02 !03 !05 +1" marks_are "!02 !03 !05 +1"

exit $((fails > 0))
}
