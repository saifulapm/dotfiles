#!/usr/bin/env bash
# A theme fragment niri rejects notifies "Config rejected" once per failure streak: again only after a good load, or from a shell started on a rejected config.
{
source "$(dirname "$0")/lib.sh"
unset TMUX

until_ok 5000 shell_status >/dev/null
notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
rejected() { notifs | jq '[.summaries[] | select(. == "Config rejected")] | length'; }
rejected_is() { [ "$(rejected)" = "$1" ]; }
frag=$XDG_STATE_HOME/dots/theme-out/niri.kdl

# niri's own stream counts its loads, so a quiet history is read only after niri has loaded what was written.
events=$DOTS_DEV_DIR/config-events
niri msg -j event-stream >"$events" 2>/dev/null &
stream=$!
trap 'kill $stream 2>/dev/null' EXIT
loads() { grep -c '^{"ConfigLoaded"' "$events"; }
until_ok 3000 eval '[ "$(loads)" -ge 1 ]'
load() {
  local n
  n=$(loads)
  "$@"
  until_ok 5000 eval '[ "$(loads)" -gt '"$n"' ]' || echo "     no ConfigLoaded after: $*"
  # The shell reads the same stream; the notification it sends then has to reach its own server.
  sleep 0.5
}
breaks() { printf 'bogus\n' >>"$frag"; }
last_loaded() { grep '^{"ConfigLoaded"' "$events" | tail -1; }

check "the shell starts on a good config with no Config rejected" rejected_is 0

load breaks
echo "     niri: $(last_loaded)"
until_ok 3000 rejected_is 1
check "a bogus line in the theme fragment notifies Config rejected" rejected_is 1
check "the Island shows Config rejected" until_ok 2000 eval 'island | jq -e ".text | test(\"Config rejected\")" >/dev/null'
entry() { jq -c '[.history[] | select(.summary == "Config rejected")][0] | {app, summary, body}' "$XDG_STATE_HOME/dots/notifications.json"; }
echo "     history: $(entry)"
check "the history entry is from niri with the body niri still runs the last good config" \
  eval '[ "$(entry)" = '"'"'{"app":"niri","summary":"Config rejected","body":"niri still runs the last good config"}'"'"' ]'

# Fast saves of a broken config, as in kak, are one streak.
had=$(rejected)
load eval 'breaks; breaks'
breaks
load breaks
check "three more rejected loads add nothing ($had before)" eval '[ "$had" = 1 ] && rejected_is 1'

had=$(rejected)
load "$repo/bin/dots" theme paper
echo "     niri: $(last_loaded)"
check "dots theme paper loads cleanly and notifies nothing ($had before)" eval '[ "$had" = 1 ] && rejected_is 1 && last_loaded | grep -q "\"failed\":false"'
load breaks
until_ok 3000 rejected_is 2
check "the next rejection after a good load notifies again" rejected_is 2

load "$repo/bin/dots" theme blueprint
had=$(rejected)
load "$repo/bin/dots" theme paper
check "a theme switch on a good config notifies nothing ($had before)" eval '[ "$had" = 2 ] && rejected_is 2 && last_loaded | grep -q "\"failed\":false"'

# The island at rest first, so a notification still held there cannot pass for this one.
until_ok 8000 eval 'island | jq -e ".mode == \"rest\"" >/dev/null'
timeout 0.5 qs ipc call notifs dnd true
load breaks
until_ok 3000 rejected_is 3
check "with Do Not Disturb on, the rejection still reaches the history" rejected_is 3
check "with Do Not Disturb on, the Island stays at rest" eval 'island | jq -e ".mode == \"rest\"" >/dev/null'
timeout 0.5 qs ipc call notifs dnd false

# niri drops a frozen shell's stream; the one the shell opens again starts with the same rejection, which is no new streak.
dropped() { grep -q "reading events too slowly" "$dev_log"; }
niri msg action spawn -- foot -c /dev/null
until_ok 5000 eval 'niri msg -j windows | jq -e "any(.[]; .app_id == \"foot\")" >/dev/null'
had=$(rejected)
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
kill -STOP "$pid"
for _ in $(seq 400); do
  niri msg action focus-workspace-down
  niri msg action focus-workspace-up
  dropped && break
done
kill -CONT "$pid"
check "niri dropped the frozen shell's event stream" dropped
sleep 1.5
check "the stream opened again on the rejected config notifies nothing ($had before)" eval '[ "$had" = 3 ] && rejected_is 3'

# A shell that starts while niri runs a rejected config tells it once: the first burst's rejection is the first it hears.
had=$(rejected)
systemctl --user kill -s KILL "$DOTS_DEV_UNIT"
# The unit restarts after 500 ms; until then the old instance's socket may still answer.
sleep 0.8
until_ok 5000 shell_status >/dev/null
until_ok 3000 rejected_is 4
sleep 1
check "a shell started on a rejected config notifies it once ($had before)" eval '[ "$had" = 3 ] && rejected_is 4'

exit $((fails > 0))
}
