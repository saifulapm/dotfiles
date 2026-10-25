#!/usr/bin/env bash
# While a film plays, a bar in the keys' place on every page shows it, a reopened Dekho adopts the run without playing it again, Shift+S stops it, and once it ends Continue watching lists it first with its new time left.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-bar-test-$$
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
note_session() { dekho_state | jq -r .releases.session >>"$sessions"; }
bar() { dekho_state | jq -c '[.page, .bar.shown, .bar.title, .bar.episode]'; }
bar_on() { dekho_is --arg p "$1" --arg t "$2" --arg e "$3" '.page == $p and .bar.shown and .bar.title == $t and .bar.episode == $e and .playing != null'; }
bar_off() { dekho_is '.bar.shown == false and .playing == null'; }
mpv_window() { niri msg -j windows | jq -c --arg t "$1" '[.[] | select(.app_id == "mpv" and .title == $t)]'; }
mpv_up() { [ "$(mpv_window "$1" | jq length)" = 1 ]; }
fake_mpv_pids() { session_qs_pids "/fake-mpv.qml"; }
nothing_left() { unit_inactive && [ -z "$(fake_mpv_pids)" ] && [ "$(niri msg -j windows | jq '[.[] | select(.app_id == "mpv")] | length')" = 0 ]; }
plays() { grep -c '^play --json' "$fake_log"; }
continued_first() { dekho_state | jq -c '.rows.continue[0] | [.title, .line]'; }
dekho_focused() { niri msg -j focused-window | jq -e '.app_id == "dekho"' >/dev/null; }
# niri focuses the window mpv maps, so the keys after it go back to Dekho by hand, with a key first to hand it niri's keymap.
refocus() {
  niri msg action focus-window --id "$(niri msg -j windows | jq '[.[] | select(.app_id == "dekho")][0].id')"
  until_ok 1000 dekho_focused
  wtype -k Shift_L
}
open_dekho() {
  niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
  until_ok 5000 dekho_up
}

exec_line=$(sed -n 's/^Exec=//p' "$entry")
open_dekho
until_ok 3000 dekho_is '(.rows.movies | length) == 10 and (.rows.continue | length) == 5'
check "with nothing playing, no page shows the bar and the keys are drawn ($(bar))" \
  dekho_is '.bar.shown == false and .playing == null and (.offline.keys | length) > 0'

# Seven Stations: Play, then Enter on Auto.
wtype jjl
until_ok 1000 dekho_is '.focus == {"row": "movies", "col": 1}'
wtype -k Return
until_ok 3000 dekho_is '.page == "title" and .title.name == "Seven Stations"'
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "buttons"'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 6'
wtype -k Return
until_ok 3000 unit_active
note_session
until_ok 8000 mpv_up "Seven Stations (2026)"
until_ok 3000 dekho_is '.releases.mode == ""'
refocus
until_ok 2000 bar_on title "Seven Stations (2026)" ""
check "once mpv plays the film, the title page shows the bar with its title ($(bar))" bar_on title "Seven Stations (2026)" ""
check "the bar names Shift+S, and stands in the keys' place ($(dekho_state | jq -c '[.bar.keys, (.title.keys | length)]'))" \
  dekho_is '(.bar.keys | map(map(ascii_downcase))) == [["⇧s", "stop"]]'

# Every page: Home, Browse, the Title page and a Person.
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
check "Home shows the bar ($(bar))" bar_on home "Seven Stations (2026)" ""
wtype f
until_ok 3000 dekho_is '.page == "browse"'
check "Browse shows the bar ($(bar))" bar_on browse "Seven Stations (2026)" ""
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Return
until_ok 3000 dekho_is '.page == "title" and .title.name == "Seven Stations" and (.title.crew | length) > 0'
wtype -k Tab
wtype -k Tab
until_ok 1000 dekho_is '.title.zone == "crew"'
wtype -k Return
until_ok 3000 dekho_is '.page == "person"'
check "a person's page shows the bar ($(bar))" bar_on person "Seven Stations (2026)" ""

# The bar in each board's look: Paper's inked tag, Artboard's tinted pill, Blueprint's bracketed accent tag in its mono face.
look() { dekho_state | jq -c '[.bar.tag, .bar.look, .releases.look.ink, .releases.look.accent]'; }
check "paper: the tag reads NOW PLAYING on ink ($(look))" \
  dekho_is '.bar.tag == "NOW PLAYING" and (.bar.look.tagFill | ascii_downcase) == (.releases.look.ink | ascii_downcase) and .bar.look.tagRadius == 0'
in_theme artboard
until_ok 3000 dekho_is '.voice == "plain"'
check "artboard: the tag reads Now playing in a rounded pill ($(look))" \
  dekho_is '.bar.tag == "Now playing" and .bar.look.tagRadius == 8 and (.bar.look.tagFill | ascii_downcase) != (.releases.look.ink | ascii_downcase)'
in_theme blueprint
until_ok 3000 dekho_is '.voice == "bracket"'
check "blueprint: the tag reads [NOW PLAYING], unfilled, in the mono face ($(look))" \
  dekho_is '.bar.tag == "[NOW PLAYING]" and .bar.look.tagFill == "#00000000" and (.bar.look.font | test("Mono"))'
in_theme paper
until_ok 3000 dekho_is '.voice == "caps"'

# Closed and reopened mid-play, Dekho adopts the run: the bar within 1 s of its first frame, and no second play.
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "Dekho closed, the film plays on" unit_active
before=$(plays)
open_dekho
framed=$(now_ms)
until_ok 1500 bar_on home "Seven Stations (2026)" ""
adopted=$(($(now_ms) - framed))
check "reopened, Home shows the bar ${adopted} ms after its first frame, within 1 s ($(bar))" \
  bash -c "[ $adopted -le 1000 ] && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.bar.shown and .bar.title == \"Seven Stations (2026)\"' >/dev/null"
check "and no second play started ($before then $(plays) plays)" test "$(plays)" = "$before"

# A capital S typed into the search field is text, not a stop.
wtype /
until_ok 1000 dekho_is '.search.focused'
wtype S
sleep 0.5
check "S typed into search is text, and the film plays on ($(dekho_state | jq -c .search.text))" \
  bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.search.text == \"S\" and .bar.shown' >/dev/null"
wtype -k BackSpace
wtype -k Escape
until_ok 1000 dekho_is '.search.focused == false'

# Shift+S stops it: within 2 s no dekho or mpv is left, the bar goes and Continue watching lists the film first.
wtype S
until_ok 2000 nothing_left
check "Shift+S leaves no unit, dekho or mpv within 2 s" nothing_left
until_ok 1000 bar_off
check "and the bar goes, the keys back ($(bar))" bar_off
until_ok 2000 dekho_is '.rows.continue[0].title == "Seven Stations"'
check "Continue watching lists Seven Stations first with its new time left ($(continued_first))" \
  dekho_is '.rows.continue[0] | .title == "Seven Stations" and .line == "1h 45 · 1h 35 left"'

# The Long Tide resumed at S3 E4: the bar names the episode; mpv quitting on its own ends it. Up to Continue watching first, then down a row, wherever the cursor was left.
wtype kkjhhl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 dekho_is '.page == "title" and .title.name == "The Long Tide" and (.title.buttons | length) == 2'
wtype r
until_ok 3000 unit_active
note_session
until_ok 8000 mpv_up "The Long Tide — S03E04  Quay Nine"
until_ok 3000 dekho_is '.releases.mode == ""'
refocus
until_ok 2000 bar_on title "The Long Tide" "S3 · E4"
check "a series' bar shows its title and S3 · E4 ($(bar))" bar_on title "The Long Tide" "S3 · E4"
niri msg action close-window --id "$(mpv_window "The Long Tide — S03E04  Quay Nine" | jq '.[0].id')"
until_ok 2000 bar_off
check "within 2 s of mpv quitting, the bar goes ($(bar))" bar_off
until_ok 2000 dekho_is '.rows.continue[0].title == "The Long Tide" and .rows.continue[0].line == "S3 E4 · 21 min left"'
check "and Continue watching lists The Long Tide first with its new time left ($(continued_first))" \
  dekho_is '.rows.continue[0] | .title == "The Long Tide" and .line == "S3 E4 · 21 min left"'
check "and its Resume reads the new time too ($(dekho_state | jq -c '[.title.buttons[].text]'))" \
  dekho_is '[.title.buttons[].text][1] == "▶ Resume · S3 E4 · 21 min left"'
refocus

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Home closes Dekho" dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
