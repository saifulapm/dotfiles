#!/usr/bin/env bash
# Dekho's toast: one line at the bottom for 2.4 s after w marks an episode, a Browse filter changes or a play fails to start; a second toast replaces the first; each board draws it in its card's look.
{
# A Return that played would start a unit on this machine's real user manager, so it gets this run's own name, stopped at the end.
export DOTS_DEKHO_UNIT=dekho-toast-test-$$
source "$(dirname "$0")/lib.sh"

dekho_qml=$repo/shell/dekho.qml
entry=$repo/home/dot_local/share/applications/dekho.desktop
work=$(mktemp -d)
runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session" "$DOTS_DEV_DIR/dekho-play-fails"
  rm -rf "$work"
}
log=$work/dekho.log

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
dekho_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "dekho")] | length'; }
dekho_up() { [ "$(dekho_windows)" = 1 ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
listed() { dekho_is '.releases.mode == "list" and (.releases.rows | length) == 5'; }
failed() { dekho_is '.releases.mode == "starting" and .releases.starting.fail.shown'; }
note_session() { dekho_state | jq -r .releases.session >>"$sessions"; }
toast_text() { dekho_state | jq -r .toast.text; }
toast_is() { dekho_is --arg t "$1" '.toast.text == $t and .toast.shown'; }
toast_shown() { dekho_is '.toast.shown'; }
toast_gone() { dekho_is '.toast.shown == false'; }
# Waits until $2 ms after the clock reading $1.
at() { local left=$(($1 + $2 - $(now_ms))); ((left > 0)) && sleep "$(awk -v ms="$left" 'BEGIN { print ms / 1000 }')"; return 0; }
look() { dekho_state | jq -c '.toast.look | [.radius, .shadow, .chamfer]'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.series | length) == 10'
check "no toast is drawn before anything asks for one ($(dekho_state | jq -c .toast))" dekho_is '.toast.shown == false'

# The Long Tide's page opens on S3 E4, next up and aired.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.cursor == 4'

wtype w
t0=$(now_ms)
until_ok 3000 toast_shown
check "w on E4 toasts Marked watched once the backend answered ($(dekho_state | jq -c .toast))" toast_is 'Marked watched'
check "and the mark is already drawn" dekho_is '.title.episodes[3].watched'
at "$t0" 2000
check "it is still drawn at 2.0 s" toast_shown
at "$t0" 3000
check "and gone by 3.0 s" toast_gone

# Browse from the Title page: series, Drama, English. t makes the kind all, so Horror, a film genre, is on the way round.
wtype f
until_ok 3000 dekho_is '.page == "browse" and (.browse.rows | length) > 0'
wtype t
until_ok 3000 toast_is 'Filter: All'
horror() { toast_is 'Filter: Horror'; }
for _ in $(seq 12); do
  horror && break
  wtype g
  sleep 0.3
done
check "g until Horror toasts Filter: Horror ($(toast_text))" horror

# Two toasts apart: the second text replaces the first and restarts the 2.4 s. The first starts the timer afresh, or a timer left running by an earlier toast would hide the missing restart.
until_ok 3000 toast_gone
wtype g
sleep 1.2
wtype g
t0=$(now_ms)
until_ok 1000 toast_is 'Filter: Mystery'
check "two g presses draw only the second text, Filter: Mystery ($(dekho_state | jq -c .toast))" dekho_is '.toast.text == "Filter: Mystery" and .toast.shown and .toast.lines == 1'
at "$t0" 1500
check "it is still drawn 1.5 s after the second press, 2.7 s after the first" toast_shown
at "$t0" 3000
check "and gone 3.0 s after the second" toast_gone

wtype x
until_ok 1000 toast_is 'Filters cleared'
check "x toasts Filters cleared ($(toast_text))" toast_is 'Filters cleared'

# A play that fails to start: the fake answers an error event with the text in this file.
wtype -k Escape
until_ok 1000 dekho_is '.page == "title"'
failing=$DOTS_DEV_DIR/dekho-play-fails
printf 'boom\nquit\xe2\x80\xaeed\x1b[31m red %0300d' 0 | tr 0 x >"$failing"
wtype -k Return
until_ok 3000 listed
wtype -k Return
until_ok 5000 failed
note_session
until_ok 1000 dekho_is '.toast.text | startswith("Could not start: ")'
check "a failed play toasts the reason on one elided line without a newline, U+202E or ESC ($(dekho_state | jq -c '.toast | {lines, truncated, shown}'))" \
  dekho_is '.toast | .shown and .lines == 1 and .truncated and (.text | startswith("Could not start: boom quit")) and (.text | test("[\n‮\u001b]") | not)'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
: >"$failing"
wtype -k Return
until_ok 3000 listed
wtype -k Return
until_ok 5000 failed
note_session
until_ok 1000 toast_is 'Could not start: dekho could not start playback'
check "a failure with no reason toasts the fallback words ($(toast_text))" toast_is 'Could not start: dekho could not start playback'
rm -f "$failing"
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'

# Each board's card look, on a toast of w's.
board() {
  in_theme "$1"
  until_ok 3000 dekho_is --arg v "$2" '.voice == $v'
  wtype w
  until_ok 3000 toast_is "$3"
  check "$1: the toast reads $3 as written ($(dekho_state | jq -c .toast.look))" dekho_is "$4"
}
board artboard plain 'Marked unwatched' '.toast.look.radius == 10 and .toast.look.shadow == false and .toast.look.chamfer == false and (.toast.look.border | ascii_downcase) == (.toast.look.accent | ascii_downcase)'
artboard_look=$(look)
board blueprint bracket 'Marked watched' '.toast.look.chamfer and .toast.look.shadow == false'
blueprint_look=$(look)
board paper caps 'Marked unwatched' '.toast.look.radius == 0 and .toast.look.shadow and .toast.look.chamfer == false and (.toast.look.border | ascii_downcase) == (.toast.look.ink | ascii_downcase)'
paper_look=$(look)
check "the three boards draw it three ways (paper $paper_look, artboard $artboard_look, blueprint $blueprint_look)" \
  test "$(printf '%s\n' "$paper_look" "$artboard_look" "$blueprint_look" | sort -u | wc -l)" = 3

wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype -k Escape
until_ok 3000 dekho_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
