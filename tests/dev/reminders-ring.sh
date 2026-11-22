#!/usr/bin/env bash
# A reminder overdue at the shell's start waits for a reminders round: it stays quiet when another machine rang it, and rings late when the round fails.
{
source "$(dirname "$0")/lib.sh"

store="$DOTS_DEV_DIR/data/dots/reminders/dev.json"
remote="$DOTS_DEV_DIR/remote/dots-sync/reminders"
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-surfaces")' >/dev/null; }
stored() { [ -e "$store" ] && jq -e "$1" "$store" >/dev/null; }
put() { jq -n "${@:2}" >"$1.tmp" && mv "$1.tmp" "$1"; }
now_s=$(date +%s)
past=$(((now_s - 300) * 1000))
# A record as the store holds it, set 15 min ago and due 5 min ago.
rec='{id: $id, text: $text, due: $due, created: ($due - 600000), ended: null, stamps: {text: ($due - 600000), due: ($due - 600000), ended: ($due - 600000)}}'
island_text() { timeout 0.5 qs ipc call island state 2>/dev/null | jq -r '.text // ""'; }
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
until_ok 10000 desk_up
mkdir -p "$remote" "$(dirname "$store")"

# Machine a rang "tea" and synced; this machine, started later with "tea" overdue, pulls a's file first.
freeze_shell
put "$store" --arg id t1 --arg text "tea" --argjson due "$past" "{version: 1, reminders: [$rec]}"
put "$remote/a.json" --arg id t1 --arg text "tea" --argjson due "$past" "{version: 1, reminders: [$rec | .ended = \"rung\" | .stamps.ended = (\$due + 1000)]}"
restart_shell
until_ok 40000 stored '.reminders[0].ended == "rung"'
check "the round brings a's rung mark into this machine's store" stored '.reminders[0].ended == "rung"'
sleep 2
check "and tea, rung on a, does not ring here" bash -c "[ \"\$(timeout 0.5 qs ipc call notifs state | jq '[.summaries[] | select(. == \"Reminder · tea\")] | length')\" = 0 ]"
check "and the round recorded the reminders unit as ok" bash -c "jq -e '.reminders.ok == true' \"$DOTS_DEV_DIR/state/dots/sync.json\" >/dev/null"

# With a remote that fails, an overdue reminder rings anyway, once, late, with the time it was due.
freeze_shell
cp "$RCLONE_CONFIG" "$DOTS_DEV_DIR/rclone.good"
printf '[Dropbox]\ntype = alias\nremote = /proc/dots-no-remote\n' >"$RCLONE_CONFIG"
rm -f "$remote/a.json"
put "$store" --arg id t2 --arg text "late tea" --argjson due "$past" "{version: 1, reminders: [$rec]}"
due_hm=$(date -d "@$((past / 1000))" +%H:%M)
restart_shell
saw=""
watch_island() {
  local t
  t=$(island_text)
  case $t in *"Reminder · late tea"*) saw=$t ;; esac
  [ -n "$saw" ]
}
until_ok 40000 watch_island
echo "     island: $saw"
check "it rings with a summary of Reminder · late tea" bash -c "[[ '$saw' == *'Reminder · late tea · rang late'* ]]"
check "and a body that says rang late and the due time $due_hm" bash -c "[[ '$saw' == *'rang late · due at $due_hm'* ]]"
check "and it is marked rung in the store" stored '.reminders[0].ended == "rung"'
sleep 2
check "notify-send ran for it once" bash -c "[ \"\$(timeout 0.5 qs ipc call notifs state | jq '[.summaries[] | select(. == \"Reminder · late tea\")] | length')\" = 1 ]"
check "and the failed round shows in sync.json" bash -c "jq -e '.reminders.ok == false' \"$DOTS_DEV_DIR/state/dots/sync.json\" >/dev/null"
mv "$DOTS_DEV_DIR/rclone.good" "$RCLONE_CONFIG"

# A shell killed after marking a ring and before its notify-send leaves the reminder rung, and the next start does not ring it.
freeze_shell
put "$store" --arg id t3 --arg text "marked tea" --argjson due "$past" "{version: 1, reminders: [$rec | .ended = \"rung\" | .stamps.ended = (\$due + 1000)]}"
restart_shell
sleep 5
check "a reminder marked rung before a crash does not ring at the next start" bash -c "[ \"\$(timeout 0.5 qs ipc call notifs state | jq '[.summaries[] | select(. == \"Reminder · marked tea\")] | length')\" = 0 ]"

exit $((fails > 0))
}
