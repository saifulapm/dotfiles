#!/usr/bin/env bash
# While a film plays, a click on the now-playing bar's stop key stops it as Shift+S does: no unit, dekho or mpv left, and the bar gone.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-mouse-bar-test-$$
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/dekho-pointer.bash"

runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$DOTS_DEV_DIR/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session" "$runtime/$DOTS_DEKHO_UNIT.show"
  pointer_stop
}

unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
note_session() { dekho_state | jq -r .releases.session >>"$sessions"; }
bar() { dekho_state | jq -c '[.page, .bar.shown, .bar.title]'; }
bar_on() { dekho_is --arg p "$1" '.page == $p and .bar.shown and .bar.title == "Seven Stations (2026)" and .playing != null'; }
bar_off() { dekho_is '.bar.shown == false and .playing == null'; }
mpv_up() { [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "mpv" and .title == "Seven Stations (2026)")] | length')" = 1 ]; }
nothing_left() { unit_inactive && [ -z "$(session_qs_pids "/fake-mpv.qml")" ] && [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length')" = 0 ]; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(dekho_id)"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}

open_dekho
until_ok 3000 dekho_is '(.rows.movies | length) == 10'
# Seven Stations: Play, then Enter on Auto.
click_on movies:1
until_ok 3000 dekho_is '.page == "title" and .title.name == "Seven Stations"'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
wtype -k Return
until_ok 3000 unit_active
note_session
until_ok 8000 mpv_up
until_ok 3000 dekho_is '.releases.mode == ""'
refocus
until_ok 2000 bar_on title
check "Seven Stations plays and its title page shows the bar ($(bar))" bar_on title

wtype -k Escape
until_ok 1000 bar_on home
click_on bar-stop
until_ok 2000 nothing_left
check "a click on Home's bar's stop key leaves no unit, dekho or mpv within 2 s" nothing_left
until_ok 1000 bar_off
check "and the bar goes ($(bar))" bar_off

exit "$fails"
}
