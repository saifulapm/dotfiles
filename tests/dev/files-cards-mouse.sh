#!/usr/bin/env bash
# Files' open-with and share cards by mouse: a click on an app row opens the marked file in it and closes the card as Enter does, hovering moves nothing, a click on the dimmed window closes the card with Files' cursor and marks as they were, and a press on the card's heading leaves it open; a click on an online machine sends to it, one on an offline machine sends nothing and the card stays.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

files_qml=$repo/shell/files.qml
ts_dir=$DOTS_DEV_DIR/tailscale
work=$(mktemp -d)
h=$work/home
log=$work/files.log
d=$h/Downloads
mkdir -p "$d" "$h/.config"
cp /usr/share/doc/lynx/test/image.jpg "$d/a.jpg"
cp /usr/share/doc/lynx/test/image.jpg "$d/b.jpg"
# imv is the default, so it is row 0 and the test viewer is a later row.
printf '[Default Applications]\nimage/jpeg=imv.desktop\n' >"$h/.config/mimeapps.list"
apps=$DOTS_DEV_DIR/data/applications
printf '#!/bin/sh\nprintf "%%s\\n" "launch $#" "$@" >>"%s"\n' "$work/args" >"$work/viewer"
chmod +x "$work/viewer"
printf '[Desktop Entry]\nType=Application\nName=Test viewer\nExec=%s %%F\nMimeType=image/jpeg;\n' "$work/viewer" >"$apps/dots-test-viewer.desktop"
update-desktop-database "$apps"
# The fake's peers are seeded before Files reads them, and put back after.
"$repo/dev/path/tailscale" status --json >/dev/null
cp "$ts_dir/status.json" "$work/status.json"
jq '(.Peer[] | select(.DNSName | startswith("iphone.")) | .DNSName) = "iPhone.taila27604.ts.net."' "$work/status.json" >"$ts_dir/status.json"
rm -f "$ts_dir/cp.log"
cleanup() {
  pointer_stop
  cp "$work/status.json" "$ts_dir/status.json"
  rm -f "$ts_dir/cp.log"
  niri msg action close-window >/dev/null 2>&1
  rm -rf "$work"
}

files_state() { timeout 0.5 qs ipc -p "$files_qml" call files state 2>/dev/null; }
files_is() { files_state | jq -e "$@" >/dev/null 2>&1; }
files_box() { timeout 0.5 qs ipc -p "$files_qml" call files box "$1" 2>/dev/null; }
files_up() { files_is '.firstFrameMs != null and .listed'; }
# Files' cursor and marks, the rows a click behind a card would change.
rows_now() { files_state | jq -c '{cursor, marked}'; }
rows_same() { [ "$(rows_now)" = "$rows" ]; }
# A click at an offset into a named box, in output pixels: "x y" is the box's corner plus the offset.
click_in() {
  local box fx fy
  box=$(files_box "$1")
  read -r fx fy < <(app_origin files)
  point click "$((fx + $(jq -r '.x | floor' <<<"$box") + $2))" "$((fy + $(jq -r '.y | floor' <<<"$box") + $3))"
}
# A click across the middle of a named box, $2 pixels down from its top: the card's heading, under the dimmed window's own area.
click_mid() {
  local box fx fy
  box=$(files_box "$1")
  read -r fx fy < <(app_origin files)
  point click "$((fx + $(jq -r '(.x + .w / 2) | floor' <<<"$box")))" "$((fy + $(jq -r '.y | floor' <<<"$box") + $2))"
}
click_row() { point click $(app_spot files "$(files_box "$1")"); }
cp_log() { cat "$ts_dir/cp.log" 2>/dev/null; }
args_are() { [ "$(cat "$work/args" 2>/dev/null)" = "$(printf 'launch 1\n%s' "$d/a.jpg")" ]; }
ow_open() { files_is '.openWith.open and (.openWith.rows | length) > 0'; }
share_open() { files_is '.share.open and .share.listed and (.share.rows | length) > 0'; }

niri msg action spawn -- sh -c "HOME='$h' XDG_CONFIG_HOME='$h/.config' XDG_DATA_HOME='$DOTS_DEV_DIR/data' DOTS_FILES_SORT=name exec dots-files >>'$log' 2>&1"
until_ok 5000 files_up
until_ok 5000 app_placed files
wtype l
until_ok 2000 files_is '.listed and (.folder | endswith("/Downloads"))'
wtype -k space
until_ok 1000 files_is '.marked == ["a.jpg"]'
rows=$(rows_now)
echo "     Files rows: $rows"

# Open with: the viewer's row is read from the list; the pointer rests over another row first.
wtype o
until_ok 3000 ow_open
vi=$(files_state | jq '.openWith.rows | map(.app) | index("dots-test-viewer.desktop")')
other=$(files_state | jq --argjson v "$vi" '[range(1; (.openWith.rows | length))] | map(select(. != $v)) | .[0]')
point move $(app_spot files "$(files_box "openwith-row:$other")")
sleep 0.4
check "the pointer resting on app row $other leaves the cursor on row 0 ($(files_state | jq -c .openWith.at))" files_is '.openWith.open and .openWith.at == 0'
click_row "openwith-row:$vi"
until_ok 3000 args_are
check "a click on app row $vi opens the marked file in the test viewer ($(tr '\n' ' ' <"$work/args"))" args_are
check "and closes the card" files_is '.openWith.open | not'
check "and Files' rows are as they were" rows_same

wtype o
until_ok 3000 ow_open
click_in openwith-outside 20 20
until_ok 1000 files_is '.openWith.open | not'
check "a click on the dimmed window closes open-with" files_is '.openWith.open | not'
check "and leaves Files' cursor and marks as they were ($(rows_now))" rows_same
check "and opens nothing more" args_are

wtype o
until_ok 3000 ow_open
click_mid openwith-outside 169
sleep 0.5
check "a click on the card's heading leaves open-with open" files_is '.openWith.open'
wtype -k Escape
until_ok 1000 files_is '.openWith.open | not'

# Share: the online and the offline machine are read from the list.
wtype s
until_ok 3000 share_open
on=$(files_state | jq '.share.rows | map(.name) | index("iPhone")')
off=$(files_state | jq '.share.rows | map(.name) | index("fedora")')
click_row "share-row:$off"
sleep 1
check "a click on the offline machine keeps the share list open" files_is '.share.open'
check "and sends nothing: no file cp, no dots-taildrop-send" bash -c "[ ! -e '$ts_dir/cp.log' ] && ! pgrep -f '[d]ots-taildrop-send' >/dev/null"
click_in share-outside 20 20
until_ok 1000 files_is '.share.open | not'
check "a click on the dimmed window closes the share list" files_is '.share.open | not'
check "and leaves Files' cursor and marks as they were ($(rows_now))" rows_same
check "and sends nothing" test ! -e "$ts_dir/cp.log"

wtype s
until_ok 3000 share_open
click_mid share-outside 175
sleep 0.5
check "a click on the share card's heading leaves it open" files_is '.share.open'

click_row "share-row:$on"
until_ok 2000 files_is '.share.open | not'
check "a click on the iPhone closes the share list" files_is '.share.open | not'
cp_is() { [ "$(cp_log)" = "file cp $d/a.jpg 100.95.3.21:" ]; }
until_ok 5000 cp_is
check "and the fake sent the marked file to the iPhone's address ($(cp_log))" cp_is

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Files' log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
