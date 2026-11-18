#!/usr/bin/env bash
# The launcher's r mode sets a reminder in this machine's file of the synced store, lists what is pending, and d removes one; the old reminders.json moves in once.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/data/dots/reminders/dev.json"
old="$DOTS_DEV_DIR/state/dots/reminders.json"
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }
# niri lists the layer Exclusive a moment before its keys arrive, so typing waits until the window has the keyboard.
open_launcher() { niri msg action spawn -- dots-call launcher toggle; until_ok 3000 state_is '.open and .query == "" and .keyboard and .settled'; }
close_launcher() { wtype -k Escape; until_ok 2000 state_is '.open == false'; }
stored() { [ -e "$store" ] && jq -e "$1" "$store" >/dev/null; }
# The store's pending records, as the launcher lists them.
pending() { stored "[.reminders[] | select(.ended == null)] | $1"; }
# Writes the store through a rename, as the shell and dots sync do, so the shell never reads half a file.
put_store() { jq -n "$@" >"$store.tmp" && mv "$store.tmp" "$store"; }
now_s=$(date +%s)
# A record as the store holds it, pending, set now.
rec='{id: $id, text: $text, due: $due, created: $now, ended: null, stamps: {text: $now, due: $now, ended: $now}}'
# The dev unit is transient, so it restarts rather than stops; the old shell is frozen first, so its file watches act on nothing written meanwhile.
freeze_shell() { kill -STOP "$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")"; }
restart_shell() {
  systemctl --user restart "$DOTS_DEV_UNIT"
  # The unit restarts after 500 ms; until then the old instance's socket may still answer.
  sleep 0.8
  until_ok 5000 shell_status >/dev/null
  until_ok 10000 desk_up
}

until_ok 5000 shell_status >/dev/null
# The reminders service is the Desk's, which loads after the paper's first frame.
until_ok 10000 desk_up

open_launcher
wtype "r 20m tea"
until_ok 3000 state_is '.mode == "reminder" and .results[0] == "tea"'
check "r 20m tea previews tea" state_is '.mode == "reminder" and .results == ["tea"] and .pending == 0'
wtype -k Return
until_ok 2000 state_is '.open == false'
check "Enter stores it in reminders/dev.json with its id, text, due, created and no end" pending 'length == 1 and .[0].text == "tea" and (.[0].id | type) == "string" and (.[0].due - .[0].created) == 1200000'
check "and closes the launcher" state_is '.open == false'
check "and writes no reminders.json" test ! -e "$old"

open_launcher
wtype "r 1h later on"
until_ok 3000 state_is '.results[0] == "later on"'
wtype -k Return
until_ok 2000 pending 'length == 2'

open_launcher
wtype "r "
until_ok 3000 state_is '.mode == "reminder" and (.results | length) == 2'
check "r lists both pending, soonest first" state_is '.results == ["tea", "later on"] and .pending == 2'
check "the first pending row sits under the pending head" state_is '(.heads[0] | test("pending"; "i")) and .heads[1] == ""'
wtype -k Tab
wtype -k j
until_ok 2000 state_is '.selected == 1'
wtype d
until_ok 2000 pending 'length == 1'
check "d on the second row marks it removed and keeps it as a marker" stored '[.reminders[] | select(.text == "later on")] | length == 1 and .[0].ended == "removed"'
check "and the list shows the one left" state_is '.results == ["tea"] and .pending == 1'
close_launcher

open_launcher
wtype "r 25:00 x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 25:00 x says it cannot set that" state_is '.results[0] | startswith("Cannot set 25:00")'
wtype -k Return
check "Enter stores nothing and keeps the launcher open" bash -c "jq -e '.reminders | length == 2' '$store' >/dev/null && timeout 0.5 qs ipc call launcher state | jq -e .open >/dev/null"
close_launcher

open_launcher
wtype "r 0m x"
until_ok 3000 state_is '.results[0] // "" | startswith("Cannot set")'
check "r 0m x says it cannot set that" state_is '.results[0] | startswith("Cannot set 0m")'
close_launcher

# A store file that does not parse refuses a new reminder in its row and is left as it is; fixed by hand, it is read again at once.
cp "$store" "$DOTS_DEV_DIR/store.good"
printf 'not json' >"$store"
open_launcher
wtype "r 5m x"
until_ok 3000 state_is '.results[0] // "" | startswith("reminders/dev.json does not parse")'
check "a broken store makes the r row say so" state_is '.results[0] | startswith("reminders/dev.json does not parse")'
wtype -k Return
check "Enter keeps the launcher open and the store as it was" bash -c "[ \"\$(cat '$store')\" = 'not json' ] && timeout 0.5 qs ipc call launcher state | jq -e .open >/dev/null"
close_launcher
mv "$DOTS_DEV_DIR/store.good" "$store"

# An old reminders.json that does not parse stays byte for byte, and nothing is set while it does not.
junk='[{"id":"a","text":"keep","due":"abc","created":0},1]'
printf '%s' "$junk" >"$old"
open_launcher
wtype "r 5m x"
until_ok 3000 state_is '.results[0] // "" | startswith("reminders.json does not parse")'
check "an old reminders.json that does not parse makes the r row start with reminders.json does not parse" state_is '.results[0] | startswith("reminders.json does not parse")'
wtype -k Return
check "Enter keeps the old file byte for byte and moves nothing" bash -c "[ \"\$(cat '$old')\" = '$junk' ] && [ ! -e '$old.migrated' ]"
close_launcher

# Fixed by hand, it moves in at once, hand-written id and all.
day_ahead=$(((now_s + 86400) * 1000))
jq -n --argjson due "$day_ahead" '[{id: "mwlvjgei-bf1", text: "renew", due: $due, created: 1763000000000}]' >"$old"
until_ok 3000 pending 'any(.[]; .id == "mwlvjgei-bf1")'
check "the fixed old file moves in with its id, text, due and created" pending "any(.[]; .id == \"mwlvjgei-bf1\" and .text == \"renew\" and .due == $day_ahead and .created == 1763000000000)"
until_ok 2000 test -e "$old.migrated"
check "and becomes reminders.json.migrated, with no reminders.json left" bash -c "[ -e '$old.migrated' ] && [ ! -e '$old' ]"

# At a start, an old file moves in once: a store already holding a reminder as rung keeps it rung, and it does not ring.
freeze_shell
rm -f "$old.migrated"
put_store --arg id "mwlvjgei-bf2" --arg text "already rang" --argjson due $(((now_s - 600) * 1000)) --argjson now $(((now_s - 900) * 1000)) "{version: 1, reminders: [$rec | .ended = \"rung\"]}"
jq -n --argjson due "$day_ahead" --argjson past $(((now_s - 600) * 1000)) '[{id: "mwlvjgei-bf1", text: "renew", due: $due, created: 1763000000000}, {id: "mwlvjgei-bf2", text: "already rang", due: $past, created: 1763000000000}]' >"$old"
restart_shell
until_ok 5000 test -e "$old.migrated"
open_launcher
wtype "r "
until_ok 3000 state_is '.results == ["renew"]'
check "after the first start the old file's pending reminder is listed, and the rung one is not" state_is '.results == ["renew"] and .pending == 1'
close_launcher
check "the rung one stays rung in the store" stored '[.reminders[] | select(.id == "mwlvjgei-bf2")][0].ended == "rung"'
check "the old file is reminders.json.migrated" bash -c "[ -e '$old.migrated' ] && [ ! -e '$old' ]"
rung() { timeout 0.5 qs ipc call notifs state 2>/dev/null | jq -e --arg t "$1" 'any(.summaries[]; . == $t)' >/dev/null; }
sleep 2
check "and the rung one does not ring again" bash -c "! timeout 0.5 qs ipc call notifs state | jq -e 'any(.summaries[]; . == \"Reminder · already rang\")' >/dev/null"
cp "$old.migrated" "$DOTS_DEV_DIR/migrated.before"
restart_shell
sleep 2
check "a second start moves nothing more" bash -c "[ ! -e '$old' ] && cmp -s '$old.migrated' '$DOTS_DEV_DIR/migrated.before'"

# A record pulled from another machine draws as one line with no control or bidi characters.
put_store --arg id "p1" --arg text "a" --argjson due $(((now_s + 3600) * 1000)) --argjson now $((now_s * 1000)) "{version: 1, reminders: [$rec | .text = \"a\\nb\" + ([8238] | implode) + \"c\" + ([27] | implode) + \"[31m\"]}"
open_launcher
wtype "r "
until_ok 3000 state_is '.results[0] == "a bc [31m"'
check "a pulled text with a newline, U+202E and ESC lists as a bc [31m" state_is '.results == ["a bc [31m"]'
close_launcher

# A merge can leave more than 50 waiting; a new one is refused and none of them is dropped.
put_store --argjson now $((now_s * 1000)) '{version: 1, reminders: [range(60) as $i | {id: ("m" + ($i | tostring)), text: "t", due: ($now + 3600000 + $i * 60000), created: $now, ended: null, stamps: {text: $now, due: $now, ended: $now}}]}'
open_launcher
wtype "r 5m tea"
until_ok 3000 state_is '.results[0] == "At most 50 reminders can wait"'
check "with 60 pending after a merge, r 5m tea says At most 50 reminders can wait" state_is '.results[0] == "At most 50 reminders can wait"'
wtype -k Return
check "and Enter keeps all 60 pending and sets nothing" pending 'length == 60'
close_launcher
put_store '{version: 1, reminders: []}'

island_state() { timeout 0.5 qs ipc call island state 2>/dev/null; }
# The island's notification text is its app, summary and body, joined by " · ".
island_says() { island_state | jq -e --arg t "$1" '.mode == "notification" and (.text | startswith("Reminders · " + $t + " · set "))' >/dev/null; }

# A reminder that came due while the shell was stopped rings when it starts.
freeze_shell
put_store --arg id "m1" --arg text "missed" --argjson due $(((now_s - 300) * 1000)) --argjson now $(((now_s - 900) * 1000)) "{version: 1, reminders: [$rec]}"
restart_shell
until_ok 60000 rung "Reminder · missed"
check "one missed while the shell was stopped rings within 60 s of its start" rung "Reminder · missed"
check "and is marked rung in the store" stored '.reminders[0].ended == "rung"'

open_launcher
wtype "r 1m tea"
until_ok 3000 state_is '.results[0] == "tea"'
wtype -k Return
set_at=$(date +%s)
until_ok 125000 island_says "Reminder · tea"
took=$(($(date +%s) - set_at))
echo "     rang after ${took} s"
check "r 1m tea rings Reminder · tea in the island 1 min later, at its own second, not the next minute's tick" bash -c "[ $took -ge 59 ] && [ $took -le 63 ]"
check "and marks it rung in the store" stored '[.reminders[] | select(.text == "tea")][0].ended == "rung"'

exit $((fails > 0))
}
