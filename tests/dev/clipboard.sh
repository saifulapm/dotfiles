#!/usr/bin/env bash
# Every copy lands in cliphist, Mod+V lists it newest first, and Enter pastes the pick into the window you came from.
source "$(dirname "$0")/lib.sh"

launcher_state() { timeout 0.5 qs ipc call launcher state 2>/dev/null; }
state_is() { launcher_state | jq -e "$1" >/dev/null; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command through niri.
mod_v() { niri msg action spawn -- qs ipc call launcher mode clipboard; }
# The nested XDG_STATE_HOME is a temp dir, so this db is never the live history.
clip() { cliphist -db-path "$XDG_STATE_HOME/dots/clips.db" "$@"; }
listed() { clip list 2>/dev/null | cut -f2- | grep -qxF "$1"; }
not_listed() { ! listed "$1"; }
count() { clip list 2>/dev/null | wc -l; }
store() { "$repo/bin/dots-clip-store"; }

until_ok 5000 shell_status >/dev/null

typed=$(mktemp -u)
cleanup() { rm -f "$typed"; }
niri msg action spawn -- foot -e sh -c "read x; echo \"\$x\" > $typed"
foot_focused() { niri msg -j windows | jq -e 'any(.[]; .is_focused and .app_id == "foot")' >/dev/null; }
until_ok 5000 foot_focused

wl-copy first
until_ok 3000 listed first
wl-copy second
until_ok 3000 listed second
check "the watcher stores both copies" test "$(count)" = 2

mod_v
until_ok 3000 state_is '.open and .mode == "clipboard" and .results[0] == "second"'
check "Mod+V lists second, then first" state_is '.mode == "clipboard" and .results[0] == "second" and .results[1] == "first"'
wtype j
until_ok 2000 state_is '.selected == 1'
check "plain j moves to the older clip" state_is '.selected == 1'
wtype -k Return
pasted() { [ "$(wl-paste 2>/dev/null)" = first ]; }
until_ok 3000 pasted
check "Enter puts first on the clipboard" pasted
until_ok 2000 state_is '.open == false'
# The launcher types after it gives the keyboard back, so the check waits before ending foot's line.
sleep 0.5
wtype -k Return
typed_ok() { [ "$(cat "$typed" 2>/dev/null)" = first ]; }
until_ok 3000 typed_ok
check "Enter types first into the foot it came from" typed_ok

wl-copy --sensitive secret
wl-copy after
until_ok 3000 listed after
check "a clip offered with x-kde-passwordManagerHint is not stored" not_listed secret

n=$(count)
head -c 10000001 /dev/zero | tr '\0' a | store
check "a clip of 10 MB and 1 byte is not stored" test "$(count)" = "$n"

printf old | store
check "the store script keeps a plain clip" listed old
old=$(clip list | awk -F'\t' '$2 == "old" { print $1 }')
sed -i "s/^$old .*/$old $(($(date +%s) - 31 * 86400))/" "$XDG_STATE_HOME/dots/clip-times"
# The prune runs at most once an hour, so the check drops its marker to run it now.
rm -f "$XDG_STATE_HOME/dots/clip-pruned"
printf new | store
check "a clip logged 31 days ago is pruned" not_listed old
check "a fresh clip survives the prune" listed new

for i in $(seq 1 501); do printf 'clip %s' "$i" | store; done
check "501 clips leave 500" test "$(count)" = 500
check "the oldest of them is gone" not_listed "clip 1"
check "the second oldest is kept" listed "clip 2"

exit $((fails > 0))
