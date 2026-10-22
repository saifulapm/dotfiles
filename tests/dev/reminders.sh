#!/usr/bin/env bash
# The launcher's r mode sets a reminder in the state dir, lists what is pending, and d deletes one.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/state/dots/reminders.json"
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
# niri lists the layer Exclusive a moment before its keys arrive, so typing waits until the window has the keyboard.
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
stored() { [ -e "$store" ] && jq -e "$1" "$store" >/dev/null; }

until_ok 5000 shell_status >/dev/null
# The reminders service is the Desk's, which loads after the paper's first frame.
until_ok 10000 desk_up

open_launcher
wtype "r 20m tea"
until_ok 3000 state_is '.mode == "reminder" and .results[0] == "tea"'
check "r 20m tea previews tea" state_is '.mode == "reminder" and .results == ["tea"] and .pending == 0'
wtype -k Return
until_ok 2000 state_is '.open == false'
check "Enter stores it with its id, text, due and created" stored 'length == 1 and .[0].text == "tea" and (.[0].id | type) == "string" and (.[0].due - .[0].created) == 1200000'
check "and closes the launcher" state_is '.open == false'

open_launcher
wtype "r 1h later on"
until_ok 3000 state_is '.results[0] == "later on"'
wtype -k Return
until_ok 2000 stored 'length == 2'

open_launcher
wtype "r "
until_ok 3000 state_is '.mode == "reminder" and (.results | length) == 2'
check "r lists both pending, soonest first" state_is '.results == ["tea", "later on"] and .pending == 2'
check "the first pending row sits under the pending head" state_is '(.heads[0] | test("pending"; "i")) and .heads[1] == ""'
wtype -k Tab
wtype -k j
until_ok 2000 state_is '.selected == 1'
wtype d
until_ok 2000 stored 'length == 1'
check "d on the second row deletes it from reminders.json" stored 'length == 1 and .[0].text == "tea"'
check "and the list shows the one left" state_is '.results == ["tea"] and .pending == 1'
close_launcher

open_launcher
wtype "r 25:00 x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 25:00 x says it cannot set that" state_is '.results[0] | startswith("Cannot set 25:00")'
wtype -k Return
check "Enter stores nothing and keeps the launcher open" bash -c "jq -e 'length == 1' '$store' >/dev/null && timeout 0.5 qs ipc call launcher state | jq -e .open >/dev/null"
close_launcher

open_launcher
wtype "r 0m x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 0m x says it cannot set that" state_is '.results[0] | startswith("Cannot set 0m")'
close_launcher

# A file that does not parse refuses a new reminder in its row and is left as it is; fixed by hand, it is read again at once.
printf 'not json' >"$store"
open_launcher
wtype "r 5m x"
until_ok 3000 state_is '.results[0] // "" | startswith("reminders.json does not parse")'
check "a broken reminders.json makes the r row say so" state_is '.results[0] | startswith("reminders.json does not parse")'
wtype -k Return
check "Enter keeps the launcher open and the file as it was" bash -c "[ \"\$(cat '$store')\" = 'not json' ] && timeout 0.5 qs ipc call launcher state | jq -e .open >/dev/null"
close_launcher
# One entry that is not a reminder breaks the file the same way, so a new one never drops it.
junk='[{"id":"a","text":"keep","due":"abc","created":0},1]'
printf '%s' "$junk" >"$store"
open_launcher
wtype "r 5m x"
until_ok 3000 state_is '.results[0] // "" | startswith("reminders.json does not parse")'
wtype -k Return
check "a reminders.json with an entry that is not a reminder refuses Enter and keeps every byte" bash -c "[ \"\$(cat '$store')\" = '$junk' ]"
close_launcher
# A forged text in the file draws as one line with no control or bidi characters.
jq -n --argjson due "$((($(date +%s) + 3600) * 1000))" '[{id: "f", text: "a\nb‮c\u001b[31md", due: $due, created: 0}]' >"$store"
open_launcher
wtype "r "
until_ok 3000 state_is '.results[0] == "a bc [31md"'
check "a stored text with a newline, ESC and U+202E is one line in the pending row" state_is '.results == ["a bc [31md"]'
close_launcher
echo '[]' >"$store"
open_launcher
wtype "r 5m x"
until_ok 3000 state_is '.results[0] == "x"'
check "once fixed by hand, r previews again without a restart" state_is '.results == ["x"]'
close_launcher

island_state() { timeout 0.5 qs ipc call island state 2>/dev/null; }
# The island's notification text is its app, summary and body, joined by " · ".
island_says() { island_state | jq -e --arg t "$1" '.mode == "notification" and (.text | startswith("Reminders · " + $t + " · set "))' >/dev/null; }
rung() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e --arg t "$1" 'any(.summaries[]; . == $t)' >/dev/null; }

# A reminder that came due while the shell was stopped rings when it starts. The dev unit is transient, so it restarts rather than stops; the running shell writes the file only when one rings, and none is due.
now=$(($(date +%s) * 1000))
jq -n --argjson now "$now" '[{id: "m1", text: "missed", due: ($now - 300000), created: ($now - 900000)}]' >"$store"
systemctl --user restart "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
until_ok 10000 desk_up
until_ok 60000 rung "Reminder · missed"
check "one missed while the shell was stopped rings within 60 s of its start" rung "Reminder · missed"
check "and leaves the file" stored 'length == 0'

open_launcher
wtype "r 1m tea"
until_ok 3000 state_is '.results[0] == "tea"'
wtype -k Return
set_at=$(date +%s)
until_ok 125000 island_says "Reminder · tea"
took=$(($(date +%s) - set_at))
echo "     rang after ${took} s"
check "r 1m tea rings Reminder · tea in the island 60 to 120 s later" bash -c "[ $took -ge 59 ] && [ $took -le 121 ]"
check "and drops it from the file" stored 'length == 0'

exit $((fails > 0))
}
