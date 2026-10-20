#!/usr/bin/env bash
# A failed dots sync round marks the margin `sync !` and lists each failing unit in Control's Route, and a good round from the launcher clears both.
{
source "$(dirname "$0")/lib.sh"

# The live rclone config reaches the real Dropbox, so nothing below runs unless both this shell and the shell unit use the dev alias remote.
under_dev() { case $1 in "$DOTS_DEV_DIR"/*) true ;; *) false ;; esac; }
under_dev "${RCLONE_CONFIG:-}" && grep -qx 'type = alias' "$RCLONE_CONFIG" || { echo "FAIL RCLONE_CONFIG is not the dev alias remote"; exit 1; }
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEV_UNIT")
grep -qzxF "RCLONE_CONFIG=$RCLONE_CONFIG" "/proc/$pid/environ" || { echo "FAIL the shell unit does not carry the dev RCLONE_CONFIG"; exit 1; }
# Nor unless the ssh unit skips (a real age key would let it read the real ~/.ssh) and the stores it merges are the dev ones.
under_dev "${DOTS_AGE_IDENTITY:-}" && [ ! -e "$DOTS_AGE_IDENTITY" ] || { echo "FAIL DOTS_AGE_IDENTITY is not a missing file in the temp dir"; exit 1; }
under_dev "${XDG_DATA_HOME:-}" || { echo "FAIL XDG_DATA_HOME is not the dev data dir"; exit 1; }
remote=$DOTS_DEV_DIR/remote

margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
marked() { margins | jq -e '.right.sync == "sync !" and (.right.text | startswith("sync !  "))' >/dev/null 2>&1; }
unmarked() { margins | jq -e '.right.sync == "" and (.right.text | startswith("sync") | not)' >/dev/null 2>&1; }
control_state() { timeout 0.5 qs ipc call control state 2>/dev/null; }
state_is() { control_state | jq -e "$@" >/dev/null 2>&1; }
# Control opens on Audio, and one Shift+Tab steps back to Route; a key sent before the keyboard arrives is lost, so it repeats while Control is still on Audio.
open_route() {
  niri msg action spawn -- dots-call control toggle
  until_ok 3000 state_is '.open and .keyboard' || return 1
  local n
  for n in 1 2 3; do
    state_is '.section == "route"' && return 0
    wtype -M shift -k Tab -m shift
    until_ok 1000 state_is '.section == "route"' && return 0
  done
  return 1
}
launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
launcher_is() { launcher_state | jq -e "$1" >/dev/null 2>&1; }

until_ok 5000 shell_status >/dev/null

open_route
until_ok 2000 state_is '.section == "route"'
echo "     route: $(control_state | jq -c '{rows, details, sync}')"
check "with no sync.json Route's Sync row reads no rounds yet" state_is '.rows[2] == "Sync" and .details[2] == "no rounds yet" and .sync == {}'
check "with no sync.json the margin has no sync !" unmarked

rm -rf "$remote"
"$repo/bin/dots" sync >/dev/null 2>&1
until_ok 3000 marked
echo "     margins: $(margins | jq -c .right)"
check "a round with the remote gone starts the margin with sync !" marked
failing_rows() { state_is '.rows == ["Questions ring on", "Do Not Disturb", "Sync", "notes", "goals", "fish", "ssh"] and .details[2] == "4 failing" and (.details[3:] | all(endswith("directory not found"))) and ([.sync[].error] | all(endswith("directory not found")))'; }
until_ok 2000 failing_rows
echo "     route: $(control_state | jq -c '{rows, details, sync}')"
check "Route lists each unit with its error" failing_rows
wtype -k Escape
until_ok 2000 state_is '.open == false'

# The launcher's sync row runs dots sync from the shell unit, with its env and a PATH without bin/.
mkdir -p "$remote"
notes_run=$(jq '.notes.lastRun' "$XDG_STATE_HOME/dots/sync.json")
niri msg action spawn -- dots-call launcher toggle
until_ok 3000 launcher_is '.open and .query == "" and .keyboard'
wtype "> sync"
until_ok 3000 launcher_is '.mode == "commands" and .results == ["sync"]'
wtype -k Return
until_ok 15000 unmarked
echo "     margins: $(margins | jq -c .right)"
check "a good round from the launcher's sync row removes sync !" unmarked
ran_again() { jq -e --argjson t "$notes_run" '.notes.lastRun > $t' "$XDG_STATE_HOME/dots/sync.json" >/dev/null 2>&1; }
until_ok 30000 ran_again
check "the launcher's sync row ran a round without bin/ on the shell's PATH" ran_again

open_route
ok_row() { state_is '.rows == ["Questions ring on", "Do Not Disturb", "Sync"] and (.details[2] | test("^ok · [0-9]{2}:[0-9]{2}$"))'; }
until_ok 2000 ok_row
echo "     route: $(control_state | jq -c '{rows, details}')"
check "Route's Sync row reads ok · HH:MM" ok_row
wtype -k Escape

status=$(shell_status)
echo "     status: $(jq -c .sync <<<"$status")"
status_units() { jq -e '.sync.notes.ok == true and .sync.goals.ok == true and (.sync.goals.lastOk | type) == "number"' <<<"$status" >/dev/null; }
check "shell status .sync holds the units after a round" status_units

# A truncated file from another machine fails the goals unit by name, while notes still sync.
printf '{"goals":' >"$remote/dots-sync/goals/other.json"
"$repo/bin/dots" sync >/dev/null 2>&1
open_route
broken_row() { state_is '.rows == ["Questions ring on", "Do Not Disturb", "Sync", "goals"] and .details[2] == "1 failing" and .sync.goals.error == "goals: skipped other.json, which does not parse" and .sync.notes.ok'; }
until_ok 2000 broken_row
echo "     route: $(control_state | jq -c '{rows, details}')"
check "Route lists the goals unit with the file that does not parse" broken_row
wtype -k Escape

exit $((fails > 0))
}
