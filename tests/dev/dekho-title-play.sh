#!/usr/bin/env bash
# A title page offers Play, which opens the release list on "Auto: let dekho decide", and Resume once history holds the title, which plays where it stopped with no list: a film played, closed and reopened, then a series resumed at the same episode and time.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-title-play-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" "$DOTS_DEKHO_UNIT-trailer.service" 2>/dev/null
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
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
stop_unit() { systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null; until_ok 3000 unit_inactive; }
note_session() { dekho_state | jq -r .releases.session >>"$sessions"; }
buttons() { dekho_state | jq -c '[.title.buttons[].text]'; }
buttons_are() { dekho_is --argjson b "$1" '[.title.buttons[].text] == $b'; }
title_is() { dekho_is --arg n "$1" '.page == "title" and .title.name == $n'; }
mpv_window() { niri msg -j windows | jq -c --arg t "$1" '[.[] | select(.app_id == "mpv" and .title == $t)]'; }
mpv_up() { [ "$(mpv_window "$1" | jq length)" = 1 ]; }
plays() { grep -cx "$1" "$fake_log"; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(niri msg -j windows | jq '[.[] | select(.app_id == "dekho")][0].id')"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}
history_first() { "$repo/bin/dev-fake-dekho" api history --limit 1 | jq -c '.items[0] | [.id, .kind, .position]'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
wtype -k Shift_L
until_ok 3000 dekho_is '(.rows.movies | length) == 10'

# Seven Stations, the second trending film, has never been played here.
wtype jjl
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 1}'
wtype -k Return
until_ok 3000 title_is "Seven Stations"
until_ok 3000 bash -c "grep -qx 'api history --limit 20' '$fake_log' && [ \$(grep -c '^api history' '$fake_log') -ge 2 ]"
check "a film with no history shows ▶ Play and its ▶ Trailer, no Resume ($(buttons))" buttons_are '["▶ Play", "▶ Trailer"]'
check "the footer lists r for resume ($(dekho_state | jq -c '[.title.keys[] | select(.[0] | ascii_downcase == "r")]'))" \
  dekho_is '[.title.keys[] | map(ascii_downcase) | select(.[0] == "r")] == [["r", "resume"]]'
before=$(plays 'play --json --id 401 --kind movie --resume')
wtype r
sleep 0.5
check "r with nothing to resume starts nothing ($(dekho_state | jq -c .releases.mode))" \
  bash -c "timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.mode == \"\"' >/dev/null && [ \$(grep -cx 'play --json --id 401 --kind movie --resume' '$fake_log') = $before ]"

# Tab reaches the buttons, and Enter on Play opens the release list on Auto.
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
check "tab reaches the buttons, Play focused ($(dekho_state | jq -c '.title.buttons'))" dekho_is '.title.zone == "buttons" and .title.buttons[0].focused'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "Enter on Play opens the release list whose first row reads Auto: let dekho decide, the cursor on it ($(dekho_state | jq -c '.releases | [.mode, .heading, .rows[0].quality, .cursor]'))" \
  dekho_is '.releases.heading == "Seven Stations" and .releases.rows[0].auto and .releases.rows[0].quality == "Auto: let dekho decide" and .releases.cursor == 0 and .chose == {"season": null, "episode": null}'
wtype -k Return
until_ok 3000 unit_active
note_session
check "Enter on Auto shows Starting and asks dekho to play the film with no release, so dekho chooses" \
  bash -c "grep -qx 'play --json --id 401 --kind movie' '$fake_log' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.mode == \"starting\"' >/dev/null"
until_ok 8000 mpv_up "Seven Stations (2026)"
check "mpv opens on the film ($(mpv_window "Seven Stations (2026)" | jq -c '[.[].title]'))" mpv_up "Seven Stations (2026)"
until_ok 3000 dekho_is '.releases.mode == ""'

# Closing mpv ends the play; the fake's history then holds the film first, ten minutes in.
niri msg action close-window --id "$(mpv_window "Seven Stations (2026)" | jq '.[0].id')"
until_ok 5000 unit_inactive
check "closing mpv ends the unit, and history holds Seven Stations 600 s in ($(history_first))" \
  bash -c "! systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && [ '$(history_first)' = '[401,\"movie\",600]' ]"
refocus

# Reopened, the film offers Resume with its time left as Continue watching words it.
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Return
until_ok 3000 title_is "Seven Stations"
until_ok 3000 buttons_are '["▶ Play", "▶ Resume · 1h 35 left", "▶ Trailer"]'
check "with history it shows ▶ Play and ▶ Resume with its time left ($(buttons))" buttons_are '["▶ Play", "▶ Resume · 1h 35 left", "▶ Trailer"]'
wtype r
until_ok 3000 unit_active
note_session
check "r starts the film with --resume and no release list ($(dekho_state | jq -c '[.page, .releases.mode]'))" \
  bash -c "grep -qx 'play --json --id 401 --kind movie --resume' '$fake_log' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.page == \"title\" and .releases.mode == \"starting\"' >/dev/null"
until_ok 8000 dekho_is '.releases.playing != null'
check "and plays it from where it stopped, 600 s in ($(dekho_state | jq -c '.releases.playing | [.title, .resumed_at]'))" \
  dekho_is '.releases.playing.title == "Seven Stations (2026)" and .releases.playing.resumed_at == 600'
until_ok 8000 mpv_up "Seven Stations (2026)"
# Starting closes on Dekho's own sight of mpv's window; a unit stopped before then leaves it waiting.
until_ok 3000 dekho_is '.releases.mode == ""'
stop_unit
refocus

# Resume pressed from the buttons does the same.
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
wtype l
until_ok 1000 dekho_is '.title.buttons[1].focused'
check "l moves the focus to Resume ($(dekho_state | jq -c '[.title.buttons[] | .focused]'))" dekho_is '[.title.buttons[] | .focused] == [false, true, false]'
wtype -k Return
until_ok 3000 unit_active
note_session
check "Enter on Resume plays with --resume too ($(plays 'play --json --id 401 --kind movie --resume') plays)" \
  test "$(plays 'play --json --id 401 --kind movie --resume')" = 2
until_ok 8000 mpv_up "Seven Stations (2026)"
# Starting closes on Dekho's own sight of mpv's window; a unit stopped before then leaves it waiting.
until_ok 3000 dekho_is '.releases.mode == ""'
stop_unit
refocus

# The Long Tide was left at S3 E4, 1260 s in: Resume plays that episode at that time, not the next.
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype khl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 dekho_is '.page == "title" and .title.name == "The Long Tide" and .title.cursor == 4'
until_ok 3000 buttons_are '["▶ Play", "▶ Resume · S3 · E4 · 31 min left", "▶ Trailer"]'
check "a series in history shows ▶ Resume with its episode and time left ($(buttons))" buttons_are '["▶ Play", "▶ Resume · S3 · E4 · 31 min left", "▶ Trailer"]'
wtype r
until_ok 3000 unit_active
note_session
until_ok 8000 dekho_is '.releases.playing != null'
check "r resumes with --resume, at S3 E4 from 1260 s ($(dekho_state | jq -c '.releases.playing | [.title, .resumed_at]'))" \
  bash -c "grep -qx 'play --json --id 101 --kind tv --resume' '$fake_log' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.releases.playing.title == \"The Long Tide — S03E04  Quay Nine\" and .releases.playing.resumed_at == 1260' >/dev/null"
until_ok 8000 mpv_up "The Long Tide — S03E04  Quay Nine"
# Starting closes on Dekho's own sight of mpv's window; a unit stopped before then leaves it waiting.
until_ok 3000 dekho_is '.releases.mode == ""'
stop_unit
refocus

# Play on a series opens the list for the episode under the cursor; tab goes from the episodes through the crew and cast, then to the buttons.
for _ in 1 2 3 4; do
  dekho_is '.title.zone == "buttons"' && break
  wtype -k Tab
  sleep 0.2
done
until_ok 1000 dekho_is '.title.zone == "buttons" and .title.buttons[0].focused'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
check "Enter on Play opens the list for S3 E4, the cursor's episode ($(dekho_state | jq -c '[.releases.heading, .chose]'))" \
  dekho_is '.releases.heading == "The Long Tide · S3 E4 · Quay Nine" and .chose == {"season": 3, "episode": 4}'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

# The focused button in each board's look: Paper inverts in ink, Artboard tints and rings in the accent, Blueprint fills in the accent.
board() {
  in_theme "$1"
  until_ok 3000 dekho_is --arg v "$2" '.voice == $v'
  check "$1: the focused button is drawn as $3 ($(dekho_state | jq -c '[.title.buttons[0] | .radius, .fill] + [.releases.look.ink, .releases.look.accent]'))" dekho_is "$4"
}
board paper caps "a square in ink" '.title.buttons[0] as $b | $b.focused and $b.radius == 0 and ($b.fill | ascii_downcase) == (.releases.look.ink | ascii_downcase)'
board artboard plain "an 8 px rounded tint" '.title.buttons[0] as $b | $b.focused and $b.radius == 8 and ($b.fill | ascii_downcase) != (.releases.look.ink | ascii_downcase)'
board blueprint bracket "a square in the accent, its words in capitals" '.title.buttons[0] as $b | $b.focused and $b.radius == 0 and ($b.fill | ascii_downcase) == (.releases.look.accent | ascii_downcase) and $b.text == "▶ PLAY"'
in_theme paper

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Home closes Dekho" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
