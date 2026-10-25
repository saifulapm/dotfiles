#!/usr/bin/env bash
# Ctrl+F in the release list opens a filter field: what is typed leaves Auto and the releases whose name holds it, Enter plays the cursor's row, esc clears the text before a second esc closes the list, and a filter that matches nothing says so.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-filter-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session"
  rm -rf "$work"
}
log=$work/dekho.log
fake_log=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
rel() { dekho_state | jq -c ".releases$1"; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
note_session() { rel .session | jq -r . >>"$sessions"; }
listed() { dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'; }
mpv_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length'; }
mpv_up() { [ "$(mpv_windows)" -gt 0 ]; }
no_mpv() { [ "$(mpv_windows)" = 0 ]; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(niri msg -j windows | jq '[.[] | select(.app_id == "dekho")][0].id')"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}
ctrl_f() {
  wtype -M ctrl f -m ctrl
  until_ok 1000 dekho_is '.releases.filter.focused'
}
# Types a filter and waits for the list to follow it.
type_filter() {
  wtype "$1"
  until_ok 1000 dekho_is --arg t "$1" '.releases.filter.text == $t'
}

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide's page opens on S3 E4, next up, which lists six rows: Auto and five releases, two of them 1080p.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.cursor == 4'
wtype -k Return
until_ok 3000 listed
check "the list opens with no filter field ($(rel .filter))" dekho_is '.releases.filter | .text == "" and .shown == false and .focused == false'
check "the keys end in ctrl+f filter ($(rel '.starting.fail.keys[-1]'))" dekho_is '.releases.starting.fail.keys[-1] == ["CTRL+F", "FILTER"]'

ctrl_f
check "Ctrl+F shows the field with the focus, the rows unchanged ($(rel .filter))" \
  dekho_is '.releases.filter.shown and .releases.filter.focused and (.releases.rows | length) == 6'
check "paper: the field draws in Maple Mono, the board's body font ($(rel .filter.family))" dekho_is '.releases.filter.family == "Maple Mono"'

type_filter 1080
check "1080 leaves Auto first and the two 1080p releases, best first ($(rel '.rows | map([.auto, .quality, .seeders])'))" \
  dekho_is '[.releases.rows[] | [.auto, .quality, .seeders]] == [[true, "Auto: let dekho decide", ""], [false, "1080p", "412"], [false, "1080p", "37"]]'
check "the count reads the releases shown ($(rel .count))" dekho_is '.releases.count == "2 releases"'
check "the cursor is back on Auto, and nothing says no match ($(rel ' | [.cursor, .noMatch]'))" \
  dekho_is '.releases.cursor == 0 and .releases.rows[0].cursor and .releases.noMatch.shown == false'
check "a release name with a newline, U+202E and ESC is matched as it draws ($(rel '.rows[2].name'))" \
  dekho_is '.releases.rows[2].name == "The LongTide [31m S03E04 1080p BluRay x264"'

wtype j
until_ok 1000 dekho_is '.releases.cursor == 1 and .releases.rows[1].cursor'
check "j in the field still moves the cursor, and types nothing ($(rel ' | [.cursor, .filter.text]'))" \
  dekho_is '.releases.cursor == 1 and .releases.filter.text == "1080" and .releases.filter.focused'
wtype -k Return
until_ok 3000 unit_active
note_session
check "Enter on the first match plays that release by its hash" \
  grep -qx 'play --json --id 101 --kind tv -s 3 -e 4 --release a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1' "$fake_log"
until_ok 5000 mpv_up
until_ok 2000 dekho_is '.releases.mode == ""'
systemctl --user stop "$DOTS_DEKHO_UNIT.service"
until_ok 3000 unit_inactive
until_ok 3000 no_mpv
refocus

# The list opens afresh: no text kept from the play.
wtype -k Return
until_ok 3000 listed
check "reopened after a play, the list has no filter and all six rows ($(rel .filter))" \
  dekho_is '.releases.filter.text == "" and .releases.filter.shown == false'
ctrl_f
type_filter xyz
check "xyz leaves Auto alone ($(rel '.rows | map(.auto)'))" dekho_is '[.releases.rows[] | .auto] == [true] and .releases.rows[0].cursor'
check "and the line below it reads No release matches xyz ($(rel .noMatch))" \
  dekho_is '.releases.noMatch == {"text": "No release matches xyz", "shown": true}'
check "the count reads 0 releases ($(rel .count))" dekho_is '.releases.count == "0 releases"'

wtype -k Escape
until_ok 1000 dekho_is '.releases.filter.text == ""'
check "esc with text clears it: six rows, the list still open, the field still focused ($(rel ' | [.mode, (.rows | length), .filter, .noMatch.shown]'))" \
  dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6 and .releases.filter.focused and .releases.noMatch.shown == false'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
check "a second esc closes the list ($(rel .mode))" dekho_is '.page == "title" and .releases.mode == ""'

wtype -k Return
until_ok 3000 listed
check "reopened, the list has no filter field and all six rows ($(rel ' | [.filter, (.rows | length)]'))" \
  dekho_is '.releases.filter.text == "" and .releases.filter.shown == false and .releases.filter.focused == false and (.releases.rows | length) == 6'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

# The field draws in each board's body font.
for theme in artboard blueprint; do
  in_theme "$theme"
  wtype -k Return
  until_ok 3000 listed
  ctrl_f
  check "$theme: the field draws in Maple Mono, the board's body font ($(rel .filter))" \
    dekho_is '.releases.filter.shown and .releases.filter.family == "Maple Mono"'
  wtype -k Escape
  until_ok 1000 dekho_is '.releases.mode == ""'
done

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
