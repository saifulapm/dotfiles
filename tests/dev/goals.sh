#!/usr/bin/env bash
# Mod+G opens Goals; its keys add, tick, reorder and delete goals through the store, and the order survives a restart.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
goals_state() { timeout 0.5 qs ipc call goals state 2>/dev/null; }
state_is() { goals_state | jq -e "$@" >/dev/null 2>&1; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_g() { niri msg action spawn -- qs ipc call goals toggle; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
# Opens Goals and waits for its own keyboard, since niri lists the layer Exclusive before its keys arrive.
open_goals() {
  until_ok 10000 desk_up
  mod_g
  until_ok 3000 state_is '.open and .keyboard'
}
# Types $2 into the prompt of kind $1 once it is up, then Enter.
answer() {
  until_ok 2000 state_is --arg k "$1" '.prompt.kind == $k' || return 1
  [ -n "$2" ] && wtype "$2"
  until_ok 2000 state_is --arg t "$2" '.prompt.text == $t' || return 1
  wtype -k Return
}
# Presses j or k until the row of kind $1 with text $2 is selected.
select_row() {
  local i n key
  for n in 1 2 3 4 5 6 7 8; do
    i=$(goals_state | jq --arg k "$1" --arg t "$2" '[.rows[] | .kind + ":" + .text] | index($k + ":" + $t)')
    [ -n "$i" ] && [ "$i" != null ] || return 1
    state_is --argjson i "$i" '.selected == $i' && return 0
    key=j
    state_is --argjson i "$i" '.selected > $i' && key=k
    wtype "$key"
    sleep 0.1
  done
  return 1
}

until_ok 5000 shell_status >/dev/null
check "the store starts empty" test ! -s "$store"
open_goals
check "Mod+G opens Goals with the keyboard" state_is '.open and .keyboard'
check "an empty Goals shows n to add a goal" state_is '.count == 0 and .hint == "n to add a goal"'

wtype n
answer title "Ship v2"
answer deadline 3d
t0=$(now_ms)
until_ok 2000 state_is '.active == ["Ship v2"] and .prompt == null'
wtype n
answer title Read
answer deadline ""
until_ok 2000 state_is '.active == ["Ship v2", "Read"]'
echo "     goals: $(goals_state | jq -c '{active, rows, prompt}')"
check "Ship v2 and Read are active, in that order" state_is '.active == ["Ship v2", "Read"] and .count == 2'
# parseDeadline counts from the start of the minute, so the deadline sits up to a minute before now + 3 d.
due_3d() { jq -e --argjson t "$t0" '.goals[] | select(.title == "Ship v2") | .deadline | . > $t + 259200000 - 62000 and . <= $t + 259200000' "$store" >/dev/null; }
check "the store holds Ship v2's deadline about now + 3 days" due_3d
read_no_deadline() { jq -e '.goals[] | select(.title == "Read") | .deadline == null' "$store" >/dev/null; }
check "and Read with no deadline" read_no_deadline

select_row goal Read
wtype t
answer task "ch 1"
until_ok 2000 state_is '[.rows[] | .kind + ":" + .text] == ["goal:Ship v2", "goal:Read", "task:ch 1"]'
echo "     goals: $(goals_state | jq -c .rows)"
check "t on Read lists ch 1 under Read" state_is '[.rows[] | .kind + ":" + .text] == ["goal:Ship v2", "goal:Read", "task:ch 1"]'
tasks_of() { jq -c --arg g "$1" '[.goals[] | select(.title == $g) | .tasks[] | .text]' "$store"; }
only_read() { [ "$(tasks_of Read)" = '["ch 1"]' ] && [ "$(tasks_of 'Ship v2')" = '[]' ]; }
check "and the store has ch 1 on Read only" only_read

select_row goal Read
wtype -M shift k -m shift
until_ok 2000 state_is '.active == ["Read", "Ship v2"]'
check "K on Read puts it above Ship v2" state_is '.active == ["Read", "Ship v2"]'
check "and keeps Read selected" state_is '.rows[.selected].text == "Read"'

systemctl --user restart "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
open_goals
until_ok 3000 state_is '.count == 2'
echo "     after restart: $(goals_state | jq -c '{active, rows}')"
check "the order survives a shell restart" state_is '.active == ["Read", "Ship v2"]'

select_row goal "Ship v2"
wtype -k space
until_ok 2000 state_is '.count == 1'
echo "     goals: $(goals_state | jq -c '{active, done, rows}')"
check "Space on Ship v2 moves it to done, and the active count reads 1" state_is '.count == 1 and .active == ["Read"] and .done == ["Ship v2"]'

select_row goal Read
wtype d
until_ok 2000 state_is '.confirm'
check "d asks to confirm" state_is '.confirm'
wtype n
until_ok 2000 state_is '.confirm == false'
sleep 0.2
check "n after d leaves Read in place, opens no prompt and drops the confirm" state_is '.active == ["Read"] and .prompt == null and .confirm == false'

wtype -k Escape
until_ok 2000 state_is '.open == false'
check "Esc closes Goals" state_is '.open == false'

exit $((fails > 0))
}
