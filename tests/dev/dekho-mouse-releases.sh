#!/usr/bin/env bash
# Dekho's release list by mouse: a click on a row, Auto included, starts it as Enter does with the cursor there, a double click starts once, a click on the dimmer or the card's header acts on nothing, as does one while the rows are asked for, a click on a filtered row starts that row, and the wheel scrolls a long list without moving the cursor, stopping at its ends.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-mouse-releases-test-$$
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session"
  pointer_stop
}
fake_log=$DOTS_DEV_DIR/dekho.log

rel() { dekho_state | jq -c ".releases$1"; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
note_session() { rel .session | jq -r . >>"$sessions"; }
listed() { dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'; }
started() { dekho_is '.releases.mode == "starting" and (.releases.starting.steps | length) > 0'; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
play_line='play --json --id 101 --kind tv -s 3 -e 4'
plays() { grep -c "^$play_line" "$fake_log"; }
row_y() { dekho_box "$1" | jq .y; }
# Esc out of Starting stops the unit and leaves the title page with its keys.
leave_starting() {
  wtype -k Escape
  until_ok 3000 unit_inactive
  until_ok 1000 dekho_is '.page == "title" and .releases.mode == ""'
}
open_list() {
  wtype -k Return
  until_ok 3000 listed
}

open_dekho
until_ok 3000 dekho_is '(.rows.series | length) == 10'
# The Long Tide is the second trending series; its page opens on S3 E4, which lists six rows.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.cursor == 4'
beneath=$(dekho_state | jq -c '.title | [.cursor, .zone]')
open_list

click_on release:1
until_ok 3000 started
note_session
check "a click on the second release starts it with the cursor there ($(rel ' | [.mode, .cursor]'))" dekho_is '.releases.mode == "starting" and .releases.cursor == 1'
check "the fake was asked to play that release" \
  grep -qx "$play_line --release b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2" "$fake_log"
leave_starting

open_list
click_on release:0
until_ok 3000 started
note_session
check "a click on Auto starts it with the cursor there ($(rel ' | [.mode, .cursor]'))" dekho_is '.releases.mode == "starting" and .releases.cursor == 0'
check "and the fake was asked to play with no --release" grep -qx "$play_line" "$fake_log"
leave_starting

open_list
before=$(plays)
at=$(spot release:3)
# shellcheck disable=SC2086
point click $at
# shellcheck disable=SC2086
point click $at
until_ok 3000 started
note_session
check "two fast clicks on one row give one Starting ($(rel ' | [.mode, .cursor]'))" dekho_is '.releases.mode == "starting" and .releases.cursor == 3'
check "and one play call ($before, then $(plays))" test "$(plays)" = $((before + 1))
leave_starting

open_list
read -r ax ay <<<"$(spot release:0)"
read -r ox oy <<<"$dekho_at"
point click $((ox + 10)) $((oy + 10))
point click "$ax" $((ay - 25))
point click "$ax" $((ay - 70))
check "a click on the dimmer and two on the card above the rows change nothing ($(rel ' | [.mode, .cursor]') $(dekho_state | jq -c '[.page, (.title | [.cursor, .zone])]'))" \
  dekho_is --argjson t "$beneath" '.releases.mode == "list" and .releases.cursor == 0 and .page == "title" and (.title | [.cursor, .zone]) == $t'

# While the list still asks for its rows, a click where a row will be acts on nothing: the fake answers 2 s late.
read -r rx ry <<<"$(spot release:1)"
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
echo 2 >"$DOTS_DEV_DIR/dekho-slow-releases"
before=$(plays)
wtype -k Return
until_ok 1000 dekho_is '.releases.mode != "" and (.releases.rows | length) == 0'
point click "$rx" "$ry"
until_ok 4000 listed
check "a click where row 1 will be, while the rows are asked for, starts nothing ($(rel ' | [.mode, .cursor]'), $before then $(plays) plays)" \
  bash -c "[ $before = \$(grep -c '^$play_line' '$fake_log') ] && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.mode == \"list\" and .releases.cursor == 0' >/dev/null"
rm -f "$DOTS_DEV_DIR/dekho-slow-releases"

# 24 releases overflow the list's 420 px, so the wheel has something to scroll.
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
echo 24 >"$DOTS_DEV_DIR/dekho-many-releases"
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 25'
top=$(row_y release:0)
wheel_on release:2 3
until_ok 1000 bash -c "[ \"\$(timeout 0.5 qs ipc -p '$dekho_qml' call dekho box release:0 | jq .y)\" != '$top' ]"
check "three notches down move the rows up 180 px, Auto out of view (Auto at $(row_y release:0), was $top)" \
  jq -ne --argjson y "$(row_y release:0)" --argjson t "$top" '$y == $t - 180'
check "and leave the cursor on Auto ($(rel .cursor))" dekho_is '.releases.cursor == 0 and .releases.mode == "list"'
wheel_on release:5 30
last_end() { dekho_box release:24 | jq '.y + .h'; }
end1=$(last_end)
wheel_on release:12 30
check "thirty notches stop with the last row at the list's foot, and thirty more move nothing ($end1, then $(last_end), list from $top)" \
  jq -ne --argjson a "$end1" --argjson b "$(last_end)" --argjson t "$top" '$a == $b and ($a - ($t + 420) | fabs) <= 1'
wheel_on release:20 -60
until_ok 1000 bash -c "[ \"\$(timeout 0.5 qs ipc -p '$dekho_qml' call dekho box release:0 | jq .y)\" = '$top' ]"
check "sixty up bring Auto back to the top ($(row_y release:0), was $top)" test "$(row_y release:0)" = "$top"
read -r ox oy <<<"$dekho_at"
point move $((ox + 10)) $((oy + 300))
point wheel 5
check "the wheel over the dimmer moves neither the rows nor the cursor ($(rel .cursor))" \
  dekho_is '.releases.mode == "list" and .releases.cursor == 0'
rm -f "$DOTS_DEV_DIR/dekho-many-releases"
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
open_list

wtype -M ctrl f -m ctrl
until_ok 1000 dekho_is '.releases.filter.focused'
wtype 1080
until_ok 1000 dekho_is '.releases.filter.text == "1080" and (.releases.rows | length) == 3'
click_on release:2
until_ok 3000 started
note_session
check "a click on the second filtered row starts that release ($(rel ' | [.mode, .cursor]'))" dekho_is '.releases.mode == "starting" and .releases.cursor == 2'
check "the fake was asked to play the 1080p with 37 seeders" \
  grep -qx "$play_line --release d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4" "$fake_log"
leave_starting

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
