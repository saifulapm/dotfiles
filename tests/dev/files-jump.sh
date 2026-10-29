#!/usr/bin/env bash
# Files' z jumps to the folder zoxide ranks first for the typed words, leaving out the one shown, and each folder Files opens ranks in zoxide.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Codes/lareys/web" "$h/Documents/invoices" "$h/Downloads"
log=$work/files.log
zo() { HOME=$h _ZO_DATA_DIR=$work/zoxide zoxide "$@"; }
zo add "$h/Codes/lareys" "$h/Documents/invoices"

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }

niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' _ZO_DATA_DIR='$work/zoxide' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
# Keys typed before niri focuses the new window go nowhere.
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .is_focused)' >/dev/null"

wtype z
until_ok 1000 files_is '.jumping'
check "z opens the jump bar ($(files_state | jq -c '{jumping, count}'))" files_is '.jumping and .count == "z "'
wtype lar
until_ok 2000 files_is '.count == "z lar → ~/Codes/lareys"'
check "lar shows where it goes ($(files_state | jq -r .count))" files_is '.count == "z lar → ~/Codes/lareys"'
wtype -k Return
until_ok 2000 files_is '.listed and (.folder | endswith("/Codes/lareys"))'
check "Enter goes there and ends the jump ($(files_state | jq -c '{folder, jumping}'))" files_is '(.folder | endswith("/Codes/lareys")) and .jumping == false'

wtype zlar
until_ok 2000 files_is '.count == "z lar · no match"'
check "the folder shown is left out, so lar now goes nowhere ($(files_state | jq -r .count))" files_is '.count == "z lar · no match"'
wtype -k Return
check "and Enter keeps the bar for more words ($(files_state | jq -c '{folder, jumping}'))" files_is '.jumping and (.folder | endswith("/Codes/lareys"))'
wtype -k Escape
until_ok 1000 files_is '.jumping == false'
check "Esc ends the jump where it was ($(files_state | jq -c '{folder, count}'))" files_is '(.folder | endswith("/Codes/lareys")) and .count == "1 item · hidden off"'

wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/lareys/web"))'
web_ranked() { zo query -l | grep -qxF "$h/Codes/lareys/web"; }
until_ok 2000 web_ranked
check "web/, opened with l, ranks in zoxide ($(zo query -l | tr '\n' ' '))" web_ranked

# Enter in the same wtype call as the words lands before zoxide answers them.
fast_ok=0
for run in 1 2 3; do
  wtype zinv -k Return
  until_ok 2000 files_is '.listed and (.folder | endswith("/Documents/invoices"))' && fast_ok=$((fast_ok + 1))
  wtype zlar -k Return
  until_ok 2000 files_is '.listed and (.folder | endswith("/Codes/lareys"))' && fast_ok=$((fast_ok + 1))
done
check "an Enter typed before zoxide answers still jumps, $fast_ok of 6" test "$fast_ok" = 6

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
