#!/usr/bin/env bash
# Goals by mouse: a click on a task ticks it as Space does and a second click unticks it; a click on a goal folds it as Enter does.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

goals_state() { timeout 0.5 qs ipc call goals state 2>/dev/null; }
state_is() { goals_state | jq -e "$@" >/dev/null 2>&1; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns Mod+G's command through niri.
open_goals() {
  until_ok 10000 desk_up
  niri msg action spawn -- dots-call goals toggle
  until_ok 3000 state_is '.open and .keyboard and .settled'
}
# Types $2 into the prompt of kind $1 once it is up, then Enter.
answer() {
  until_ok 2000 state_is --arg k "$1" '.prompt.kind == $k' || return 1
  [ -n "$2" ] && wtype "$2"
  until_ok 2000 state_is --arg t "$2" '.prompt.text == $t' || return 1
  wtype -k Return
}
rows() { goals_state | jq -c '{selected, rows: [.rows[] | [.kind, .text, .done]]}'; }

until_ok 5000 shell_status >/dev/null
open_goals
wtype n
answer title Read
answer deadline ""
until_ok 2000 state_is '.active == ["Read"] and .prompt == null'
wtype t
answer task "ch 1"
until_ok 2000 state_is '.prompt == null and (.rows | length) == 2'
wtype t
answer task "ch 2"
until_ok 2000 state_is '.prompt == null and (.rows | length) == 3'
check "Read lists ch 1 and ch 2 with ch 2 selected ($(rows))" state_is '[.rows[] | .kind + ":" + .text] == ["goal:Read", "task:ch 1", "task:ch 2"] and .selected == 2'

click_box goals-row:1
until_ok 2000 state_is '.rows[1].done'
check "a click on ch 1 selects and ticks it, and only it ($(rows))" state_is '.selected == 1 and .rows[1].done and (.rows[2].done | not)'
click_box goals-row:1
until_ok 2000 state_is '.rows[1].done == false'
check "a second click unticks it ($(rows))" state_is '.selected == 1 and .rows[1].done == false'

click_box goals-row:0
until_ok 2000 state_is '(.rows | length) == 1'
check "a click on the Read heading selects it and folds its tasks ($(rows))" state_is '.selected == 0 and [.rows[] | .kind + ":" + .text] == ["goal:Read"]'

wtype -k Escape
until_ok 2000 state_is '.open == false'

exit $((fails > 0))
}
