#!/usr/bin/env bash
# Mod+G before the Desk has read the goals store opens nothing and logs no error; once the store is read, Mod+G opens Goals.
{
# The goals service sets its store's path only after `mkdir -p` of the store's folder exits, so a mkdir first on PATH holds that call until the flag file shows (60 s at most); every other mkdir runs at once. dots-dev hands PATH to the shell.
fake=$(mktemp -d)
printf '#!/bin/sh\ncase "$*" in\n*/dots/goals) i=0; while [ ! -e %s/release ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done ;;\nesac\nexec /usr/bin/mkdir "$@"\n' "$fake" >"$fake/mkdir"
chmod +x "$fake/mkdir"
export PATH=$fake:$PATH
source "$(dirname "$0")/lib.sh"
cleanup() { touch "$fake/release"; rm -rf "$fake"; }

store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
goals_state() { timeout 0.5 qs ipc call goals state 2>/dev/null; }
state_is() { goals_state | jq -e "$@" >/dev/null 2>&1; }
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
margins() { timeout 0.5 qs ipc call margins state 2>/dev/null; }
desk_up() { niri msg -j layers | jq -e 'any(.[]; .namespace == "dots-margins")' >/dev/null; }

# A goal on disk the held store has not read: the margin names it only once the store loads.
/usr/bin/mkdir -p "$(dirname "$store")"
node --input-type=module -e "const G = await import('$repo/shell/lib/goals.mjs'); console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'Ship v2', null, Date.now(), 'g0')))" >"$store"

until_ok 10000 desk_up
sleep 1
check "with the store held, the margin names no goal ($(margins | jq -c .right.goal))" bash -c "timeout 0.5 qs ipc call margins state | jq -e '.right.goal == \"\"' >/dev/null"
niri msg action spawn -- dots-call goals toggle
sleep 1
check "Mod+G before the store is read leaves the island at rest ($(island | jq -c '{surface, mode}'))" bash -c "timeout 0.5 qs ipc call island state | jq -e '.surface == null' >/dev/null"
check "and Goals not open ($(goals_state | jq -c '{open, opens}'))" state_is '.open == false'
errors=$(qml_errors)
[ -n "$errors" ] && echo "$errors"
check "and the shell's journal has no QML error" test -z "$errors"

touch "$fake/release"
read_store() { margins | jq -e '.right.goal == "Ship v2"' >/dev/null 2>&1; }
until_ok 5000 read_store
check "once the mkdir exits, the store is read and the margin names Ship v2 ($(margins | jq -c .right.goal))" read_store
niri msg action spawn -- dots-call goals toggle
until_ok 3000 state_is '.open and .keyboard and .settled'
check "Mod+G now opens Goals on the island ($(island | jq -c .surface))" bash -c "timeout 0.5 qs ipc call island state | jq -e '.surface == \"goals\"' >/dev/null"
check "listing Ship v2" state_is '.active == ["Ship v2"]'
wtype -k Escape
until_ok 3000 state_is '.open == false'

exit $((fails > 0))
}
