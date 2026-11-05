#!/usr/bin/env bash
# Files by mouse: a click selects one row, Shift and Ctrl clicks extend it, a double click opens, a drag starts only past 6 px and carries the selection, the wheel scrolls without moving it, and no click acts behind a question or a card.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
h=$work/home
mkdir -p "$h/Downloads" "$h/many" "$h/.config"
for i in 1 2 3 4 5 6 7 8; do printf 'f%s' "$i" >"$h/Downloads/f0$i.txt"; done
for i in $(seq -w 1 200); do : >"$h/many/n$i.txt"; done
# Each opened file lands in this viewer's log, the default app for text/plain in Files' own config.
apps=$DOTS_DEV_DIR/data/applications
mkdir -p "$apps"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>"%s"\n' "$work/opened" >"$work/viewer"
chmod +x "$work/viewer"
printf '[Desktop Entry]\nType=Application\nName=Mouse viewer\nExec=%s %%F\nMimeType=text/plain;\n' "$work/viewer" >"$apps/dots-test-mouse-viewer.desktop"
update-desktop-database "$apps"
printf '[Default Applications]\ntext/plain=dots-test-mouse-viewer.desktop\n' >"$h/.config/mimeapps.list"
log=$work/files.log
cleanup() {
  pointer_stop
  kill "$target" 2>/dev/null
  rm -f "$apps/dots-test-mouse-viewer.desktop"
  rm -rf "$work"
}

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
files_box() { timeout 0.5 qs ipc -p "$files_qml" call files box "$1" 2>/dev/null; }
# The output point a third of the way across row or click area $1, clear of its name's end.
spot() { app_spot files "$(files_box "$1")" "${2:-0.33}"; }
at() {
  local p
  p=$(spot "$1") || { echo "no row or click area named $1 is drawn in Files"; return 1; }
  # shellcheck disable=SC2086
  point click $p
}
opened() { cat "$work/opened" 2>/dev/null; }

export DROP_OUT=$DOTS_DEV_DIR/drops.json
env -u QS_CONFIG_PATH qs -p "$repo/dev/drop-target.qml" >"$DOTS_DEV_DIR/drop-target.log" 2>&1 &
target=$!
until_ok 5000 bash -c "niri msg -j windows | jq -e 'any(.[]; .title == \"drop-target\")' >/dev/null"
niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' DOTS_FILES_SORT=name exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
win_id() { niri msg -j windows | jq -r --arg t "$1" '[.[] | select(.app_id == $t or .title == $t)][0].id'; }
niri msg action toggle-window-floating --id "$(win_id drop-target)"
niri msg action move-floating-window --id "$(win_id drop-target)" -x 10 -y 60
niri msg action set-window-width --id "$(win_id drop-target)" 400
# Files opens floating.
niri msg action move-floating-window --id "$(win_id files)" -x 450 -y 60
niri msg action focus-window --id "$(win_id files)"
until_ok 2000 app_placed files
# A window opened since wtype's last key gets niri's keymap; a Shift first hands it wtype's.
wtype -k Shift_L
drop_count() { jq length "$DROP_OUT" 2>/dev/null || echo 0; }
drops_more() { test "$(drop_count)" -gt "$1"; }
read -r tx ty < <(app_origin drop-target)
tx=$((tx + 150)) ty=$((ty + 200))
# Carries a pressed row's drag over the drop target and lets go, then waits for the drop.
drop_it() {
  local n
  n=$(drop_count)
  point move "$tx" "$ty" 30
  point sleep 300
  point release
  until_ok 3000 drops_more "$n"
  niri msg action focus-window --id "$(win_id files)"
}
# The last drop's files by name, on one line.
uris() { jq -r '.[-1].uriList' "$DROP_OUT" | tr -d '\r' | sed "s|file://$h/Downloads/||" | grep . | paste -sd ' '; }

# Behaviour 2: a double click on a folder enters it.
p=$(spot Downloads)
# shellcheck disable=SC2086
point dclick $p
check "a double click on Downloads enters it and the path names it ($(files_state | jq -c '[.folder, .path]'))" \
  until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads")) and (.path | endswith("Downloads"))'

# Behaviour 1: click, Shift-click, Ctrl-click; the keys then act on that selection.
at f03.txt
check "a click on the third file selects only it ($(files_state | jq -c '[.cursor, .marked]'))" until_ok 1000 files_is '.cursor == "f03.txt" and .marked == []'
# shellcheck disable=SC2046
mod_click shift $(spot f06.txt)
check "a Shift-click on the sixth selects files 3 to 6 ($(files_state | jq -c '[.cursor, .marked]'))" \
  until_ok 1000 files_is '.cursor == "f06.txt" and .marked == ["f03.txt", "f04.txt", "f05.txt", "f06.txt"]'
# shellcheck disable=SC2046
mod_click ctrl $(spot f04.txt)
check "a Ctrl-click on the fourth leaves 3 selected ($(files_state | jq -c .marked))" until_ok 1000 files_is '.marked == ["f03.txt", "f05.txt", "f06.txt"]'
wtype y
check "y copies the files the mouse selected ($(files_state | jq -c .op.yank))" until_ok 1000 files_is '.op.yank == "copy 3"'

# Behaviour 3: a drag of a selected row carries the whole selection.
read -r x y <<<"$(spot f05.txt)"
point press "$x" "$y"
point move "$((x + 40))" "$((y + 30))" 10
check "a drag from a selected row carries all 3 ($(files_state | jq -c '[.dragging, .chip]'))" until_ok 2000 files_is '.dragging and .chip == "3 files"'
drop_it
check "and drops all 3 ($(uris))" test "$(uris)" = "f03.txt f05.txt f06.txt"

# A press moved 5 px is a click; one moved 7 px is a drag. Qt's MouseArea starts the drag on the motion after the one that crosses its threshold, so each move ends with a 1 px jitter back, as a hand's does.
read -r x y <<<"$(spot f01.txt)"
point press "$x" "$y"
point move "$((x + 5))" "$y" 5
point move "$((x + 4))" "$y" 1
point sleep 300
dragged=$(files_state | jq .dragging)
point release
check "a press moved 5 px starts no drag ($dragged)" test "$dragged" = false
check "and selects only that file on release ($(files_state | jq -c '[.cursor, .marked]'))" until_ok 1000 files_is '.cursor == "f01.txt" and .marked == [] and (.dragging | not)'
read -r x y <<<"$(spot f02.txt)"
point press "$x" "$y"
point move "$((x + 7))" "$y" 7
point move "$((x + 6))" "$y" 1
check "a press moved 7 px starts a drag ($(files_state | jq -c .dragging))" until_ok 2000 files_is '.dragging and .chip == "1 file"'
drop_it
check "which drops only that file ($(uris))" test "$(uris)" = f02.txt

# A slow double click is two clicks; a quick one opens the file in its default app.
p=$(spot f07.txt)
# shellcheck disable=SC2086
point dclick $p 700
sleep 1
check "two clicks 700 ms apart select f07 and open nothing ($(opened))" bash -c "[ -z \"\$(cat '$work/opened' 2>/dev/null)\" ]"
check "  and f07 is the cursor ($(files_state | jq -c .cursor))" files_is '.cursor == "f07.txt" and .marked == []'
p=$(spot f08.txt)
# shellcheck disable=SC2086
point dclick $p
check "a double click on f08 opens it in its default app ($(opened))" until_ok 4000 bash -c "grep -qsx '$h/Downloads/f08.txt' '$work/opened'"

# No click acts behind a question, a field or a card: each opens, a row is clicked, and nothing moves.
behind() {
  local why=$1 open=$2 shut=$3
  shift 3
  wtype "$@"
  until_ok 2000 files_is "$open"
  was=$(files_state | jq -c '[.cursor, .marked]')
  at f02.txt
  point sleep 300
  check "a click behind $why moves nothing ($was -> $(files_state | jq -c '[.cursor, .marked]'))" files_is --argjson w "$was" '[.cursor, .marked] == $w'
  # A click outside a card may have closed it already, and an Esc then would close Files.
  if files_is "$open"; then wtype -k Escape; fi
  until_ok 2000 files_is "$shut"
}
behind "the trash question" '.asking == "trash"' '.asking == ""' d
behind "a rename" '.renaming' '.renaming | not' r
behind "the find field" '.finding' '.finding | not' /
behind "the jump field" '.jumping' '.jumping | not' z
behind "open with" '.openWith.open' '.openWith.open | not' o
behind "the share card" '.share.open' '.share.open | not' s

# The wheel scrolls a folder of 200 files and leaves the selection where it was.
wtype h
until_ok 2000 files_is '.listed and .cursor == "Downloads"'
p=$(spot many)
# shellcheck disable=SC2086
point dclick $p
until_ok 2000 files_is '.listed and (.folder | endswith("/many")) and (.rows | length) == 200'
at n003.txt
# shellcheck disable=SC2046
mod_click shift $(spot n005.txt)
until_ok 1000 files_is '.marked == ["n003.txt", "n004.txt", "n005.txt"]'
before=$(files_box n020.txt | jq .y)
wheel_at=$(spot n010.txt)
# shellcheck disable=SC2086
point move $wheel_at
point wheel 3
after=$(files_box n020.txt | jq .y)
check "three notches down scroll the list ($before -> $after)" test "$(jq -n "$before - $after >= 150")" = true
check "and the selection stays ($(files_state | jq -c '[.cursor, .marked]'))" files_is '.cursor == "n005.txt" and .marked == ["n003.txt", "n004.txt", "n005.txt"]'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
