#!/usr/bin/env bash
# Files' / finds rows or opens the one place it names, . shows dotfiles, and the preview reads an image's real size, in each theme with names in their own case.
{
source "$(dirname "$0")/lib.sh"

files_qml=$repo/shell/files.qml
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
h=$work/home
mkdir -p "$h/Downloads/screenshots" "$h/Documents" "$h/Codes" "$h/Pictures"
for n in IMG_2039.jpg IMG_2040.jpg invoice-0912.pdf; do : >"$h/Downloads/$n"; done
gm convert -size 4032x3024 xc:'#c8381e' "$h/Downloads/IMG_2041.jpg"
: >"$h/Downloads/.hidden-note"
log=$work/files.log

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t' >/dev/null; }

niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' exec dots-files >>'$log' 2>&1"
until_ok 5000 files_is '.listed and .firstFrameMs != null'
# Keys typed before niri focuses the new window go nowhere.
until_ok 3000 bash -c "niri msg -j windows | jq -e 'any(.[]; .app_id == \"files\" and .is_focused)' >/dev/null"

wtype /down
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
check "/down opens Downloads, the one place it starts, and ends the find ($(files_state | jq -c '{folder, finding, query}'))" \
  files_is '(.folder | endswith("/Downloads")) and .finding == false and .query == ""'

wtype /2041
until_ok 1000 files_is '.query == "2041"'
check "/ then 2041 leaves only IMG_2041.jpg ($(files_state | jq -c .rows))" files_is '.rows == ["IMG_2041.jpg"]'
check "and the path line shows the query ($(files_state | jq -r .count))" files_is '.count == "/ 2041"'
until_ok 3000 files_is '.preview.dims != "" and .preview.image'
check "the preview of IMG_2041.jpg reads 4032 × 3024 and draws the picture ($(files_state | jq -c .preview))" \
  files_is '.preview.shown and .preview.dims == "4032 × 3024" and (.preview.kind | endswith(" · JPEG image")) and .preview.image'
wtype -k Return
until_ok 1000 files_is '.finding == false'
check "Enter ends the find and keeps its rows" files_is '.finding == false and .rows == ["IMG_2041.jpg"]'
wtype /2040
until_ok 1000 files_is '.query == "2040"'
check "a second / starts a new find, not the last one's tail ($(files_state | jq -c .query))" files_is '.query == "2040" and .rows == ["IMG_2040.jpg"]'
wtype -k Return
wtype /
wtype -k Escape
until_ok 1000 files_is '.finding == false and .query == ""'
check "/ then Esc clears the find, every row back ($(files_state | jq '.rows | length'))" files_is '(.rows | length) == 5'

check "dotfiles are hidden at first" files_is '(.rows | index(".hidden-note")) == null and .hidden == false'
wtype .
until_ok 1000 files_is '.hidden'
check ". shows dotfiles ($(files_state | jq -c .count))" files_is '(.rows | index(".hidden-note")) != null and (.count | endswith("hidden on"))'
wtype .
until_ok 1000 files_is '.hidden == false'
check ". again hides them" files_is '(.rows | index(".hidden-note")) == null'

"$repo/bin/dots" theme blueprint >/dev/null
until_ok 2000 status_theme blueprint
until_ok 2000 files_is '.voice == "bracket"'
wtype /2041
until_ok 1000 files_is '.rows == ["IMG_2041.jpg"]'
check "in Blueprint, IMG_2041.jpg draws in its real case ($(files_state | jq -c '.drawn.name'))" files_is '.drawn.name == "IMG_2041.jpg"'
check "while Blueprint's preview kind is in caps ($(files_state | jq -c .preview.kind))" files_is '.preview.kind | endswith(" · JPEG IMAGE")'
"$repo/bin/dots" theme paper >/dev/null

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
