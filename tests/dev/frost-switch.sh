#!/usr/bin/env bash
# dots theme frost switches the whole desktop within 350 ms of the call by the shell's own end stamp, three times out of three: the outgoing theme's 220 ms transition after dots theme's render and the shell's rebinding, the budget transition.sh and hifi-sweep.sh hold every theme to.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null
status_at_rest() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_at_rest paper

for run in 1 2 3; do
  # Paper's sheet settles and its passage draws before the next switch, so each run starts from rest.
  sleep 1
  start=$(now_ms)
  "$repo/bin/dots" theme frost >/dev/null
  until_ok 2000 status_at_rest frost
  ended=$(shell_status | jq -r '.transitionEndedAt')
  took=$((ended - start))
  check "run $run: the switch into Frost ended $took ms after the call (at most 350)" test "$ended" -ge "$start" -a "$took" -le 350
  check "run $run: the state file reads frost" test "$(cat "$XDG_STATE_HOME/dots/theme")" = frost
  "$repo/bin/dots" theme paper >/dev/null
  until_ok 3000 status_at_rest paper
done

exit $((fails > 0))
}
