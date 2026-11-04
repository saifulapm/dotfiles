#!/usr/bin/env bash
# dots theme frost plays the frost switch, and its motion lasts at most 300 ms by the shell's own start and end stamps, three times out of three; leaving Frost plays it too.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

paper_layer() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-paper" and .layer == "Background")' >/dev/null; }
until_ok 5000 paper_layer
until_ok 5000 shell_status >/dev/null
status_at_rest() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }

# Switches to $1 and prints the first running transition status reports, then waits for rest; the polls only name the kind, the stamps time it.
kind_of_switch() {
  local seen="" s
  "$repo/bin/dots" theme "$1" >/dev/null &
  local pid=$!
  for _ in $(seq 60); do
    s=$(shell_status | jq -r '.transition')
    [ -n "$s" ] && [ "$s" != null ] && { seen=$s; break; }
    status_at_rest "$1" && break
  done
  wait "$pid"
  until_ok 3000 status_at_rest "$1"
  echo "$seen"
}

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_at_rest paper

for run in 1 2 3; do
  # Paper's sheet settles and its passage draws before the next switch, so each run starts from rest.
  sleep 1
  start=$(now_ms)
  "$repo/bin/dots" theme frost >/dev/null
  until_ok 2000 status_at_rest frost
  read -r began ended < <(shell_status | jq -r '"\(.transitionStartedAt) \(.transitionEndedAt)"')
  took=$((ended - began))
  echo "     run $run: the motion began $((began - start)) ms after the call and ended $((ended - start)) ms after it"
  check "run $run: the frost switch's motion took $took ms (at most 300)" test "$began" -ge "$start" -a "$took" -le 300
  check "run $run: the state file reads frost" test "$(cat "$XDG_STATE_HOME/dots/theme")" = frost
  "$repo/bin/dots" theme paper >/dev/null
  until_ok 3000 status_at_rest paper
done

sleep 1
kind=$(kind_of_switch frost)
check "paper to frost: status reports transition frost ($kind)" test "$kind" = frost
sleep 1
kind=$(kind_of_switch blueprint)
check "frost to blueprint: status reports transition frost ($kind)" test "$kind" = frost

errors=$(journalctl --user -u "$DOTS_DEV_UNIT" --no-pager -o cat | grep -E 'Failed to load|ShaderEffect|QShader|\.qsb|Paper.qml')
[ -n "$errors" ] && echo "$errors"
check "the shell's journal has no load or shader error" test -z "$errors"

exit $((fails > 0))
}
