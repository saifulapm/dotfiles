#!/usr/bin/env bash
# A title with a trailer offers Trailer, and t or the button plays it in its own mpv window under a unit of its own: it never stops a film, Starting waits on the film's own window past it, the film's Stop leaves it, and it is never recorded in history. A title with none offers nothing, and a trailer that cannot start toasts.
{
# The nested App and its units run on this machine's real user manager, so this run's units have a name of their own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-trailer-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
trailer_unit=$DOTS_DEKHO_UNIT-trailer
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" "$trailer_unit.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session" "$runtime/$trailer_unit.log" "$runtime/$trailer_unit.session" "$DOTS_DEV_DIR/dekho-trailer-fails"
  rm -rf "$work"
}
log=$work/dekho.log
fake_log=$DOTS_DEV_DIR/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
film_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
film_inactive() { ! film_active; }
trailer_active() { systemctl --user is-active --quiet "$trailer_unit.service"; }
trailer_inactive() { ! trailer_active; }
note_session() { dekho_state | jq -r '.releases.session, .trailer.session' >>"$sessions"; }
buttons() { dekho_state | jq -c '[.title.buttons[].text]'; }
# The page has its answer once the meta line, drawn from it alone, is filled in.
title_is() { dekho_is --arg n "$1" '.page == "title" and .title.name == $n and .title.meta != ""'; }
mpv_window() { niri msg -j windows | jq -c --arg t "$1" '[.[] | select(.app_id == "mpv" and .title == $t)]'; }
mpv_count() { mpv_window "$1" | jq length; }
mpv_up() { [ "$(mpv_count "$1")" = 1 ]; }
mpv_gone() { [ "$(mpv_count "$1")" = 0 ]; }
lines() { grep -c "$1" "$fake_log"; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(niri msg -j windows | jq '[.[] | select(.app_id == "dekho")][0].id')"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}
history_all() { "$repo/bin/dev-fake-dekho" api history; }
film="Seven Stations (2026)"
trailer="Seven Stations (2026) — Trailer"
trailer_line='trailer --json --id 401 --kind movie'

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.movies | length) == 10'

# A Quiet Verdict, the first trending film, has no trailer.
wtype jj
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 0}'
wtype -k Return
until_ok 3000 title_is "A Quiet Verdict"
check "a title with no trailer shows no Trailer button ($(buttons))" dekho_is 'all(.title.buttons[]; .text != "▶ Trailer")'
before=$(lines '^trailer')
wtype t
sleep 1
check "t on it starts no trailer unit and asks dekho for no trailer ($(lines '^trailer') trailer lines)" \
  bash -c "! systemctl --user is-active --quiet '$trailer_unit.service' && [ \$(grep -c '^trailer' '$fake_log') = $before ]"

# Seven Stations, the second, has one.
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype l
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 1}'
wtype -k Return
until_ok 3000 title_is "Seven Stations"
check "a title with a trailer shows ▶ Play first and ▶ Trailer last ($(buttons))" dekho_is '.title.buttons[0].text == "▶ Play" and .title.buttons[-1].text == "▶ Trailer"'
check "the footer lists t for trailer ($(dekho_state | jq -c '[.title.keys[] | select(.[0] | ascii_downcase == "t")]'))" \
  dekho_is '[.title.keys[] | map(ascii_downcase) | select(.[0] == "t")] == [["t", "trailer"]]'
history_before=$(history_all)
wtype t
until_ok 3000 trailer_active
note_session
check "t starts the trailer unit $trailer_unit and asks dekho for the film's trailer" \
  bash -c "systemctl --user is-active --quiet '$trailer_unit.service' && [ \$(grep -cx '$trailer_line' '$fake_log') = 1 ]"
until_ok 8000 mpv_up "$trailer"
check "mpv opens on the trailer ($(mpv_window "$trailer" | jq -c '[.[].title]'))" mpv_up "$trailer"
check "and the film's unit does not run" film_inactive
first=$(mpv_window "$trailer" | jq '.[0].id')
refocus

# The button does the same, and a second trailer replaces the first.
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
n=$(dekho_state | jq '.title.buttons | length')
for _ in $(seq 2 "$n"); do wtype l; done
until_ok 1000 dekho_is '.title.buttons[-1].focused'
wtype -k Return
until_ok 3000 bash -c "[ \$(grep -cx '$trailer_line' '$fake_log') = 2 ]"
note_session
replaced() { trailer_active && [ "$(mpv_window "$trailer" | jq --argjson f "$first" '[.[] | select(.id != $f)] | length')" = 1 ] && mpv_up "$trailer"; }
until_ok 8000 replaced
check "Enter on Trailer plays it again in its unit, in one trailer window that replaced the first ($(mpv_window "$trailer" | jq -c '[.[].id]'), first $first)" replaced
check "and the film's unit still does not run" film_inactive
refocus

# Play while the trailer is open: Starting waits on the film's window, not the trailer's.
wtype h
until_ok 1000 dekho_is '.title.buttons[0].focused'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
wtype -k Return
until_ok 3000 film_active
note_session
until_ok 8000 dekho_is '.releases.playing != null'
# The fake maps the film's window 1.5 s after playing; two of Starting's 500 ms probes see only the trailer's.
sleep 0.8
check "Starting stays up while only the trailer's window is open ($(dekho_state | jq -c .releases.mode), film windows $(mpv_count "$film"))" \
  bash -c "timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.mode == \"starting\"' >/dev/null && [ \"\$(niri msg -j windows | jq --arg t '$film' '[.[] | select(.app_id == \"mpv\" and .title == \$t)] | length')\" = 0 ]"
until_ok 8000 mpv_up "$film"
until_ok 3000 dekho_is '.releases.mode == ""'
check "Starting closes once the film's window maps ($(dekho_state | jq -c .releases.mode))" dekho_is '.releases.mode == ""'
check "then both units run and both windows are open" bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && systemctl --user is-active --quiet '$trailer_unit.service' && [ \"\$(niri msg -j windows | jq --arg f '$film' --arg t '$trailer' '[.[] | select(.app_id == \"mpv\" and (.title == \$f or .title == \$t))] | length')\" = 2 ]"

# Closing the trailer's window ends its unit alone.
niri msg action close-window --id "$(mpv_window "$trailer" | jq '.[0].id')"
until_ok 3000 trailer_inactive
check "closing the trailer's window ends its unit within 3 s" trailer_inactive
check "the film's unit runs on and its window stays open" bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && [ \"\$(niri msg -j windows | jq --arg f '$film' '[.[] | select(.app_id == \"mpv\" and .title == \$f)] | length')\" = 1 ]"
check "history is as it was before the trailers" test "$(history_all)" = "$history_before"
refocus

# The film's Stop, as the bar runs it, leaves a trailer playing.
wtype t
until_ok 3000 trailer_active
note_session
until_ok 8000 mpv_up "$trailer"
check "a trailer started with the film playing leaves the film's unit active and its window open" bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && [ \"\$(niri msg -j windows | jq --arg f '$film' '[.[] | select(.app_id == \"mpv\" and .title == \$f)] | length')\" = 1 ]"
"$repo/bin/dots-dekho-play" --stop
until_ok 3000 mpv_gone "$film"
check "the film's stop ends the film's unit and its window" bash -c "! systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && [ \"\$(niri msg -j windows | jq --arg f '$film' '[.[] | select(.app_id == \"mpv\" and .title == \$f)] | length')\" = 0 ]"
check "the trailer's unit and window stay" bash -c "systemctl --user is-active --quiet '$trailer_unit.service' && [ \"\$(niri msg -j windows | jq --arg t '$trailer' '[.[] | select(.app_id == \"mpv\" and .title == \$t)] | length')\" = 1 ]"
"$repo/bin/dots-dekho-play" --trailer --stop
until_ok 3000 mpv_gone "$trailer"
refocus

# A trailer that cannot start says so.
printf 'no network' >"$DOTS_DEV_DIR/dekho-trailer-fails"
# An earlier toast lasts 2.4 s, so the one t draws is told apart from it.
until_ok 3000 dekho_is '.toast.shown == false'
wtype t
until_ok 3000 dekho_is '.toast.shown and .toast.text == "Trailer could not start"'
note_session
check "a trailer that cannot start toasts Trailer could not start within 3 s ($(dekho_state | jq -c .toast.text))" dekho_is '.toast.shown and .toast.text == "Trailer could not start"'
check "and leaves no trailer unit running" trailer_inactive
rm -f "$DOTS_DEV_DIR/dekho-trailer-fails"

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Home closes Dekho" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
