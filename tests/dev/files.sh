#!/usr/bin/env bash
# Files is an App: Mod+Y starts its own qs process with one window in the theme, a second Mod+Y focuses it, and Esc ends the process; its places and rows move by keys, even keys typed before a folder's rows land.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads/screenshots/old" "$h/Downloads/taildrop" "$h/Codes" "$h/Pictures" "$h/Documents" "$h/.config/gtk-3.0"
for i in 1 2 3 4 5 6 7; do : >"$h/Downloads/screenshots/shot-$i.png"; done
for n in IMG_2039.jpg IMG_2040.jpg IMG_2041.jpg invoice-0912.pdf notes.txt; do : >"$h/Downloads/$n"; done
# Names any sender can choose: a newline, a right-to-left override and ESC, and 250 characters, near ext4's 255-byte limit.
forged=$(printf 'zz-forged\n\xe2\x80\xae\x1bname.txt')
: >"$h/Downloads/$forged"
long="zzz-$(printf 'x%.0s' {1..246})"
: >"$h/Downloads/$long"
printf 'file://%s/Codes lareys\nfile://%s/Documents invoices\n' "$h" "$h" >"$h/.config/gtk-3.0/bookmarks"
log=$work/files.log

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
files_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "files")] | length'; }
files_up() { [ "$(files_windows)" = 1 ] && files_is '.firstFrameMs != null'; }
files_gone() { [ "$(files_windows)" = 0 ]; }
files_pids() { session_qs_pids "-p $files_qml"; }
no_files_process() { [ -z "$(files_pids)" ]; }
# niri runs no binds for wtype's virtual keyboard, so the check spawns the bind's command, dots-files, through niri.
mod_y() { niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"; }

mod_y
until_ok 5000 files_up
check "Mod+Y opens one window whose app id is files ($(files_windows))" files_up
check "its first frame came $(files_state | jq .firstFrameMs) ms after the process started, under 500" \
  files_is '(.firstFrameMs | type) == "number" and .firstFrameMs > 0 and .firstFrameMs < 500'
check "its title is the folder, Home ($(niri msg -j windows | jq -r '.[] | select(.app_id == "files") | .title'))" \
  bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .title == \"Home\")' >/dev/null"
check "the header reads FILES · Home · MOD Y in Paper ($(files_state | jq -c .head))" \
  files_is '.head == {"label": "FILES", "folder": "Home", "chip": "MOD Y"}'

# A drive mounted on this machine lists between the pins and Trash, and is no part of this check.
check "the places are Home, Downloads, Codes, Pictures, Documents, the two bookmarks under PINNED, and Trash ($(files_state | jq -c .places))" \
  files_is '[.places[] | select(startswith("drives:") | not)] == ["places:Home", "places:Downloads", "places:Codes", "places:Pictures", "places:Documents", "pinned:lareys", "pinned:invoices", "trash:Trash"]'
until_ok 2000 files_is '.listed'
wtype jj
until_ok 1000 files_is '.cursor == "Downloads"'
wtype l
until_ok 2000 files_is '.listed and .folder == "'"$h"'/Downloads"'
check "l on Downloads/ lists it folders first ($(files_state | jq -c '.rows[0:3]'))" files_is '.rows[0:2] == ["screenshots", "taildrop"] and .cursor == "screenshots"'
wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/screenshots"))'
check "l on screenshots/ lists its 8 entries, the folder first ($(files_state | jq -c .rows))" \
  files_is '(.rows | length) == 8 and .rows[0] == "old" and .dirs == ["old"]'
check "the status line reads the cursor's path, the counts and its place ($(files_state | jq -c .status))" \
  files_is '.status | {path, counts, at} == {"path": "~/Downloads/screenshots/old", "counts": "8 items · 1 folder · 7 files · 0 marked", "at": "1 of 8"}'
check "and the path draws whole, with room beside it (finding #KYZ754D8)" files_is '.status.pathElided == false'
wtype h
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
check "h goes back up with the cursor on screenshots/ ($(files_state | jq -r .cursor))" files_is '.cursor == "screenshots"'

# l then j in one wtype call: the j lands before screenshots/ is listed and must move in its rows, not in Downloads'.
early_ok=0
for run in 1 2 3 4 5; do
  wtype lj
  until_ok 2000 files_is '.listed and (.folder | endswith("/screenshots"))'
  files_is '.cursor == "shot-1.png"' && early_ok=$((early_ok + 1))
  wtype h
  until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads")) and .cursor == "screenshots"'
done
check "a j typed before screenshots/ is listed moves in its rows, $early_ok of 5 runs" test "$early_ok" = 5

wtype jj
until_ok 1000 files_is '.cursor == "IMG_2039.jpg"'
wtype -k space -k space
until_ok 1000 files_is '(.marked | length) == 2'
check "space marks IMG_2039.jpg and IMG_2040.jpg and steps down ($(files_state | jq -c '{marked, cursor}'))" \
  files_is '.marked == ["IMG_2039.jpg", "IMG_2040.jpg"] and .cursor == "IMG_2041.jpg"'
check "the status line counts them ($(files_state | jq -r .status.counts))" files_is '.status.counts | endswith(" · 2 marked")'
wtype k
until_ok 1000 files_is '.cursor == "IMG_2040.jpg"'
check "the marked cursor row draws its mark ($(files_state | jq -c .drawn))" files_is '.drawn.mark == "■" and .drawn.name == "IMG_2040.jpg"'

row_at() { files_state | jq --arg n "$1" '.rows | index($n)'; }
go_to() {
  local at by key=j
  at=$(files_state | jq .selected)
  by=$(($(row_at "$1") - at))
  ((by < 0)) && key=k by=$((-by))
  for ((; by > 0; by--)); do wtype "$key"; done
  until_ok 1000 files_is --arg n "$1" '.cursor == $n'
}
go_to "$forged"
check "a name with a newline, U+202E and ESC draws on one line, without them ($(files_state | jq -c .drawn))" \
  files_is '.drawn.lines == 1 and (.drawn.name | test("[\\n\u202e\u001b]") | not) and (.drawn.name | startswith("zz-forged"))'
go_to "$long"
check "a 250-character name draws on one elided line ($(files_state | jq -c '.drawn | {lines, elided}'))" files_is '.drawn.lines == 1 and .drawn.elided'

wtype -k Tab
until_ok 1000 files_is '.side == "places"'
check "tab moves to the places, on Downloads ($(files_state | jq -c '{side, placeAt}'))" files_is '.side == "places" and .placeAt == 1'
wtype jjjj
wtype -k Return
until_ok 2000 files_is '.listed and .side == "list" and (.folder | endswith("/Codes"))'
check "j to lareys under PINNED and Enter opens ~/Codes, back in the list ($(files_state | jq -r .folder))" files_is '.side == "list" and (.folder | endswith("/Codes"))'

niri msg action spawn -- foot -c /dev/null
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"foot\" and .is_focused)' >/dev/null"
pid=$(files_pids)
mod_y
files_focused() { niri msg -j windows | jq -e 'any(.[]; .app_id == "files" and .is_focused)' >/dev/null; }
until_ok 3000 files_focused
check "a second Mod+Y focuses the open window and starts no second process" \
  bash -c "[ \"\$(niri msg -j windows | jq '[.[] | select(.app_id == \"files\")] | length')\" = 1 ] && [ '$(files_pids)' = '$pid' ]"

wtype -k Escape
until_ok 3000 files_gone
check "Esc closes the window" files_gone
until_ok 3000 no_files_process
check "and its process exits" no_files_process
# Its children go with it: qs dies on SIGTERM without ending them, and the drives watch would run on.
watch_left() { local p; for p in $(pgrep -x findmnt); do tr '\0' '\n' 2>/dev/null <"/proc/$p/environ" | grep -qx "HOME=$h" && return 0; done; return 1; }
no_watch_left() { ! watch_left; }
until_ok 3000 no_watch_left
check "and no findmnt watch of its own is left running" no_watch_left

mod_y
until_ok 5000 files_up
niri msg action close-window
until_ok 3000 no_files_process
check "closing the window from niri ends the process too" no_files_process

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
