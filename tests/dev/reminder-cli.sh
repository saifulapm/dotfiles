#!/usr/bin/env bash
# The reminder CLI against a running shell: what reminder add sets the launcher's r mode lists, reminder rm takes it off, and one added while the shell is stopped rings at its due second after the start.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/data/dots/reminders/dev.json"
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
# The CLI runs as an agent's would, on the nested session's data dir; mise keeps its own dirs, or its node shim installs node afresh there.
reminder() { env $mise_dirs "$repo/bin/reminder" "$@"; }
listed() { open_launcher; wtype "r "; until_ok 3000 state_is "$1"; }
freeze_shell() { kill -STOP "$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")"; }
restart_shell() {
  systemctl --user restart "$DOTS_DEV_UNIT"
  sleep 0.8
  until_ok 5000 shell_status >/dev/null
  until_ok 10000 desk_up
}
rung() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e --arg t "$1" 'any(.summaries[]; . == $t)' >/dev/null; }

until_ok 5000 shell_status >/dev/null
until_ok 10000 desk_up

# The shell started with no store file, so the CLI's merge makes it while the shell watches the folder.
check "the store does not exist before the first add" test ! -e "$store"
out=$(reminder add 20m tea)
echo "     $out"
due_clock=$(jq -r '.reminders[0].due / 1000 | strflocaltime("%H:%M")' "$store")
check "reminder add 20m tea prints tea · in 20m · its clock time" test "$out" = "tea · in 20m · $due_clock"
listed '.mode == "reminder" and .results == ["tea"]'
check "the launcher's r lists tea" state_is '.results == ["tea"] and .pending == 1'
close_launcher

id=$(jq -r '.reminders[0].id' "$store")
lists_it() { [[ $(reminder list) =~ ^$id\ +$due_clock\ +tea$ ]]; }
check "reminder list prints it with its id" lists_it
out=$(reminder rm "$id")
check "reminder rm <id> prints removed: tea" test "$out" = "removed: tea"
listed '.mode == "reminder" and .results == []'
check "and the launcher no longer lists it" state_is '.results == [] and .pending == 0'
close_launcher

# Added while the shell is stopped, it is in the store the next start reads, and rings at its own second.
freeze_shell
reminder add 1m stretch
set_at=$(date +%s)
restart_shell
until_ok 75000 rung "Reminder · stretch"
took=$(($(date +%s) - set_at))
echo "     rang after ${took} s"
check "one added while the shell was stopped rings 1 min after the add" bash -c "[ $took -ge 59 ] && [ $took -le 63 ]"
check "and is marked rung in the store" bash -c "jq -e '[.reminders[] | select(.text == \"stretch\")][0].ended == \"rung\"' '$store' >/dev/null"

exit $((fails > 0))
}
