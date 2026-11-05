#!/usr/bin/env bash
# Deen by mouse: a click on a tab opens it; a click on a Duas or Hadith row does what Enter does there; a wheel notch scrolls a long list; a pointer resting on a row while j is pressed never moves the selection.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

deen_qml=$repo/shell/deen.qml
entry=$repo/home/dot_local/share/applications/deen.desktop
work=$(mktemp -d)
cleanup() {
  pointer_stop
  rm -rf "$work"
}
log=$work/deen.log
calls=$DOTS_DEV_DIR/deen.log

deen_state() { timeout 0.5 qs ipc -p "$deen_qml" call deen state 2>/dev/null; }
deen_is() { deen_state | jq -e "$@" >/dev/null 2>&1; }
duas() { deen_state | jq -c ".duas | ${1:-.}"; }
duas_is() { deen_state | jq -e ".duas | $1" >/dev/null 2>&1; }
hadith() { deen_state | jq -c ".hadith | $1"; }
hadith_is() { deen_state | jq -e ".hadith | $1" >/dev/null 2>&1; }
deen_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "deen")] | length'; }
deen_up() { [ "$(deen_windows)" = 1 ] && deen_is '.firstFrameMs != null'; }
deen_box() { timeout 0.5 qs ipc -p "$deen_qml" call deen box "$1" 2>/dev/null; }
# The output point in the middle of a named click area in Deen's window.
deen_spot() { app_spot deen "$(deen_box "$1")" || { echo "no click area named $1 is drawn" >&2; return 1; }; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
calls_has() { grep -qx "$1" "$calls" 2>/dev/null; }
fixture=$repo/dev/deen/dua-list.json
ch3=$(jq -c '.chapters[2].bn' "$fixture")
ch1=$(jq -c '.chapters[0].bn' "$fixture")

# The corpus is ready, so Hadith opens on its collections.
echo ready >"$DOTS_DEV_DIR/deen-hadith"
exec_line=$(sed -n 's/^Exec=//p' "$entry")
until_ok 3000 status_theme artboard
niri msg action spawn -- sh -c "DOTS_DEEN=$repo/bin/dev-fake-deen DOTS_DEV_DIR=$DOTS_DEV_DIR exec $exec_line >>'$log' 2>&1"
until_ok 5000 deen_up
float_app deen

at=$(deen_spot deen-tab:duas)
# shellcheck disable=SC2086
point click $at
until_ok 3000 duas_is '.rows | length > 0'
check "a click on the Duas tab opens Duas ($(deen_state | jq -c '[.tab, .heading]'))" deen_is '.tab == "duas" and .heading == "Duas"'

at=$(deen_spot deen-duas-row:4)
# shellcheck disable=SC2086
point move $at
wtype j
until_ok 1000 duas_is '.cursor == 1'
sleep 0.3
check "j under a pointer resting on the fifth chapter moves the cursor to chapter 1, not the hovered one ($(duas .cursor))" duas_is '.cursor == 1'
wtype k
until_ok 1000 duas_is '.cursor == 0'

at=$(deen_spot deen-duas-row:2)
# shellcheck disable=SC2086
point move $at
point wheel 1
until_ok 1000 duas_is '.rows[0].inView | not'
check "one wheel notch down over the 268 chapters moves the first shown row off the top ($(duas '.rows[0] | [.text, .inView]'))" \
  duas_is '(.rows | length) > 10 and ([.rows[] | select(.text == '"$ch1"' and .inView)] | length == 0)'

at=$(deen_spot deen-duas-row:2)
# shellcheck disable=SC2086
point click $at
until_ok 2000 duas_is ".pane.title == $ch3"
check "a click on the third chapter opens it as Enter does, the cursor on it ($(duas '[.pane.title, .pane.head, .cursor]'))" \
  duas_is ".pane.title == $ch3 and .pane.head == \"dua 1 of 1\" and .cursor == 2"

at=$(deen_spot deen-tab:hadith)
# shellcheck disable=SC2086
point click $at
until_ok 3000 hadith_is '.ready and .count == 10'
check "a click on the Hadith tab opens Hadith on its collections ($(deen_state | jq -c '[.tab, .heading]'))" deen_is '.tab == "hadith" and .hadith.level == "collections"'

at=$(deen_spot deen-hadith-row:8)
# shellcheck disable=SC2086
point click $at
until_ok 2000 hadith_is '.level == "books"'
check "a click on the ninth collection lists its books as Enter does ($(hadith '[.level, .heading, .cursor]'))" \
  hadith_is '.level == "books" and .heading == "চল্লিশ হাদীসে কুদসী"'
check "it asked deen for Qudsi's books" calls_has 'hadith books qudsi'

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "Deen's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

niri msg action close-window --id "$(app_window_id deen)"
exit $((fails > 0))
}
