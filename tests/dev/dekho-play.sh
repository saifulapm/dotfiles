#!/usr/bin/env bash
# Enter on an episode lists its releases best first, Enter on one starts playback in a transient user unit while Starting draws its progress and steps, esc stops the unit, and Continue watching resumes.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-play-test-$$
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
dekho_gone() { [ "$(dekho_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
in_theme() { "$repo/bin/dots" theme "$1" >/dev/null; until_ok 3000 status_theme "$1"; }
title_loaded() { dekho_is '.page == "title" and .title.season > 0 and (.title.episodes | length) > 0'; }
rel() { dekho_state | jq -c ".releases$1"; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
note_session() { rel .session | jq -r . >>"$sessions"; }
listed() { dekho_is '.releases.mode == "list" and (.releases.rows | length) == 5'; }
started() { dekho_is '.releases.mode == "starting" and (.releases.starting.steps | length) > 0'; }
buffering() { dekho_is '.releases.mode == "starting" and .releases.starting.down != ""'; }

exec_line=$(sed -n 's/^Exec=//p' "$entry")
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 dekho_up
until_ok 3000 dekho_is '(.rows.series | length) == 10'

# The Long Tide is the second trending series; its page opens on S3 E4, next up.
wtype jl
until_ok 1000 dekho_is '.focus == {"row": "series", "col": 1}'
wtype -k Return
until_ok 3000 title_loaded
until_ok 3000 dekho_is '.title.cursor == 4'
wtype -k Return
until_ok 3000 listed
check "Enter on next up, S3 E4, draws the release list over the title page ($(dekho_state | jq -c '[.page, .releases.mode, .releases.header, .releases.heading, .releases.count]'))" \
  dekho_is '.page == "title" and .releases.shown and .releases.header == "RELEASE" and .releases.heading == "The Long Tide · S3 E4 · Quay Nine" and .releases.count == "5 releases" and .chose == {"season": 3, "episode": 4}'
check "the fake heard the releases call for S3 E4" grep -qx 'api releases --id 101 --kind tv -s 3 -e 4' "$fake_log"
check "the rows draw best first, by seeders then size, with quality, size, seeders and audio ($(rel '.rows | map([.quality, .size, .seeders, .audio])'))" \
  dekho_is '[.releases.rows[] | [.quality, .size, .seeders, .audio]] == [["720p", "1.1 GB", "530", "EN 2.0"], ["1080p", "2.1 GB", "412", "EN 5.1"], ["720p", "614 MB", "412", ""], ["2160p", "12.4 GB", "88", "EN 5.1"], ["1080p", "8.4 GB", "37", "EN 5.1 ES 2.0"]]'
check "the cursor is on the best, the only row tagged ($(rel '.rows | map([.best, .cursor])'))" \
  dekho_is '.releases.cursor == 0 and [.releases.rows[] | .best] == ["BEST", "", "", "", ""] and .releases.rows[0].cursor'
check "a release name and audio with a newline, U+202E and ESC draw on one line without them ($(rel '.rows[4] | [.name, .lines, .audio]'))" \
  dekho_is '.releases.rows[4] | .lines == 1 and .audioLines == 1 and (.name | test("[\n‮\u001b]") | not) and (.audio | test("[\n‮]") | not)'
check "a 300-character release name draws on one elided line ($(rel '.rows[2] | [.lines, .truncated]'))" \
  dekho_is '.releases.rows[2] | .lines == 1 and .truncated'
check "paper: the cursor row inverts in ink and the card casts Paper's hard shadow ($(rel '.look | [.cursorFill, .ink, .shadow]'))" \
  dekho_is '.releases.look | (.cursorFill | ascii_downcase) == (.ink | ascii_downcase) and .shadow and .chamfer == false'

wtype -k Return
until_ok 3000 unit_active
note_session
check "Enter on the best starts the test unit $DOTS_DEKHO_UNIT" unit_active
check "the fake was asked to play that release" grep -qx 'play --json --id 101 --kind tv -s 3 -e 4 --release b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2' "$fake_log"
# Starting is read every 100 ms until it goes: the fill and the step names, in the order they came.
fills=()
order=$work/order
: >"$order"
paper_look=
deadline=$(($(now_ms) + 8000))
while (($(now_ms) < deadline)); do
  s=$(dekho_state)
  [ "$(jq -r .releases.mode <<<"$s")" = starting ] || break
  fills+=("$(jq .releases.starting.fill <<<"$s")")
  jq -r '.releases.starting.steps[].text' <<<"$s" >>"$order"
  if [ -z "$paper_look" ] && jq -e '(.releases.starting.steps | length) > 0' <<<"$s" >/dev/null; then paper_look=$(jq -c '.releases | [.starting.release, .look.barFill, .look.accent, .look.markRadius]' <<<"$s"); fi
  sleep 0.1
done
steps=$(awk '!seen[$0]++' "$order" | paste -sd '|')
# Two different values between empty and full: a tail that drew the buffers in one burst shows at most one.
rising() {
  local prev=-1 f mids=
  for f in "${fills[@]}"; do
    awk -v a="$f" -v b="$prev" 'BEGIN { exit !(a >= b) }' || return 1
    awk -v a="$f" 'BEGIN { exit !(a > 0 && a < 1) }' && mids+="$f"$'\n'
    prev=$f
  done
  (($(sort -u <<<"$mids" | grep -c .) >= 2))
}
check "Starting's progress rose through at least two values between empty and full, never going back (${fills[*]})" rising
check "the steps appeared in order ($steps)" test "$steps" = "Found 530 seeders|Connected to peers|Buffering the start of the file|mpv starts at 108 MB"
check "paper: the bar fills in the accent and the marks are square, under the stream's quality and size ($paper_look)" \
  bash -c "jq -e '.[0] == \"720p · 1.1 GB\" and (.[1] | ascii_downcase) == (.[2] | ascii_downcase) and .[3] == 0' <<<'$paper_look' >/dev/null"
until_ok 2000 dekho_is '.releases.mode == ""'
check "on playing, Starting goes and the title page is back, the play kept ($(dekho_state | jq -c '[.page, .releases.mode, .releases.playing.event]'))" \
  dekho_is '.page == "title" and .releases.mode == "" and .releases.shown == false and .releases.playing.event == "playing"'
check "and the unit plays on behind it" unit_active

# A play that fails before it plays: the fake answers an error event and exit 1 with the text in this file.
failing=$DOTS_DEV_DIR/dekho-play-fails
play_line='play --json --id 101 --kind tv -s 3 -e 4 --release b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2'
plays() { grep -cx "$play_line" "$fake_log"; }
failed() { dekho_is '.releases.mode == "starting" and .releases.starting.fail.shown'; }
fail_fills() { dekho_is --arg t "$1" '.releases.starting.fail.text == $t and .releases.starting.fail.lines == 1'; }
printf 'no source answered for this release' >"$failing"
wtype -k Return
until_ok 3000 listed
wtype -k Return
until_ok 5000 failed
note_session
check "an error before playing leaves Starting stuck no more: it draws the error on one line ($(rel .starting.fail))" fail_fills 'no source answered for this release'
check "the progress, the steps and the swarm are gone, only the failure is drawn ($(rel '.starting.shown'))" \
  dekho_is '.releases.starting.shown == false and .releases.starting.fail.shown'
check "the keys are r try again and esc back, in Paper's capitals ($(rel '.starting.fail.keys'))" \
  dekho_is '.releases.starting.fail.keys == [["R", "TRY AGAIN"], ["ESC", "BACK"]]'
before=$(plays)
printf 'boom\nquit\xe2\x80\xaeed\x1b[31m red' >"$failing"
wtype r
until_ok 5000 bash -c "[ \$(grep -cx '$play_line' '$fake_log') = $((before + 1)) ]"
until_ok 5000 failed
note_session
check "r runs the same play again: the fake heard it a second time ($before, then $(plays))" test "$(plays)" = $((before + 1))
check "an error with a newline, U+202E and ESC draws on one line without them ($(rel .starting.fail))" \
  dekho_is '.releases.starting.fail | .lines == 1 and (.text | startswith("boom quit")) and (.text | test("[\n‮\u001b]") | not)'
printf '%0300d' 0 | tr 0 x >"$failing"
wtype r
until_ok 5000 dekho_is '.releases.starting.fail.shown | not'
until_ok 5000 failed
note_session
check "a 300-character error draws on one elided line ($(rel '.starting.fail | [.lines, .truncated]'))" \
  dekho_is '.releases.starting.fail | .lines == 1 and .truncated and (.text | length) == 300'
: >"$failing"
wtype r
until_ok 5000 dekho_is '.releases.starting.fail.shown | not'
until_ok 5000 failed
note_session
check "an error with no text still says something ($(rel .starting.fail.text))" dekho_is '.releases.starting.fail.text == "dekho could not start playback"'
rm -f "$failing"
wtype r
until_ok 5000 dekho_is '.releases.mode == "" and .releases.playing != null'
note_session
check "r once the cause is gone plays: Starting goes and the title page is back ($(dekho_state | jq -c '[.page, .releases.mode, .releases.playing.event]'))" \
  dekho_is '.page == "title" and .releases.mode == "" and .releases.playing.event == "playing"'
check "and the unit plays on" unit_active
printf 'no source answered' >"$failing"
wtype -k Return
until_ok 3000 listed
wtype -k Return
until_ok 5000 failed
note_session
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
rm -f "$failing"
check "esc on the failure goes back to the title page and the unit is stopped ($(dekho_state | jq -c '[.page, .releases.mode]'))" \
  bash -c "! systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.page == \"title\" and .releases.mode == \"\"' >/dev/null"

# A second run, cancelled.
wtype -k Return
until_ok 3000 listed
wtype -k Return
until_ok 4000 started
until_ok 2000 unit_active
note_session
pid=$(systemctl --user show -p MainPID --value "$DOTS_DEKHO_UNIT.service")
wtype -k Escape
until_ok 3000 unit_inactive
check "esc in Starting stops the unit within 3 s" unit_inactive
check "and the fake it ran, pid $pid, is gone" bash -c "[ '${pid:-0}' -gt 0 ] && ! kill -0 '$pid' 2>/dev/null"
check "esc leaves the title page with its keys ($(dekho_state | jq -c '[.page, .releases.mode]'))" dekho_is '.page == "title" and .releases.mode == ""'

# S3 E3 has no releases.
wtype k
until_ok 1000 dekho_is '.title.cursor == 3'
wtype -k Return
until_ok 3000 dekho_is '.releases.mode == "none"'
check "an episode with no releases draws the board's words ($(rel '.none'))" \
  dekho_is '.releases.none.shown and .releases.none.head == "No releases found" and .releases.none.why == "Both sources answered and neither lists this episode yet." and .releases.heading == "The Long Tide · S3 E3 · Salt and Iron"'
wtype r
until_ok 3000 bash -c "[ \$(grep -cx 'api releases --id 101 --kind tv -s 3 -e 3' '$fake_log') = 2 ]"
check "r asks again: the fake heard a second releases call for S3 E3 ($(grep -cx 'api releases --id 101 --kind tv -s 3 -e 3' "$fake_log"))" \
  bash -c "[ \$(grep -cx 'api releases --id 101 --kind tv -s 3 -e 3' '$fake_log') = 2 ]"
until_ok 3000 dekho_is '.releases.mode == "none"'
wtype -k Escape
until_ok 1000 dekho_is '.releases.mode == ""'
check "esc goes back to the title page" dekho_is '.page == "title" and .releases.mode == ""'

# Each board's own detail, on S3 E4's list and Starting.
wtype j
until_ok 1000 dekho_is '.title.cursor == 4'
board() {
  in_theme "$1"
  until_ok 3000 dekho_is --arg v "$2" '.voice == $v'
  wtype -k Return
  until_ok 3000 listed
  check "$1: $3 ($(rel .look) $(rel '.rows[0].best'))" dekho_is "$4"
  wtype -k Return
  until_ok 4000 buffering
  note_session
  check "$1: $5 ($(rel '.starting | [.percent, .down]') $(rel .look))" dekho_is "$6"
  wtype -k Escape
  until_ok 3000 unit_inactive
  until_ok 1000 dekho_is '.releases.mode == ""'
}
board artboard plain "the card is rounded 14 px, the cursor row 10 px, and best is written small, as the Artboard board draws them" \
  '.releases.look.cardRadius == 14 and .releases.look.cursorRadius == 10 and .releases.rows[0].best == "best" and .releases.header == "Release"' \
  "the step marks are circles and the bar is rounded 4 px, as the Artboard board draws them" \
  '.releases.look.markRadius == 8 and .releases.look.barRadius == 4'
board blueprint bracket "the card's corners are cut and best reads [BEST], as the Blueprint board draws them" \
  '.releases.look.chamfer and .releases.look.shadow == false and .releases.rows[0].best == "[BEST]" and .releases.count == "5 RELEASES"' \
  "Starting writes its numbers in capitals, BUFFERING and MB/S DOWN, as the Blueprint board writes them" \
  '(.releases.starting.percent | test("^BUFFERING [0-9]+%$")) and (.releases.starting.down | test("^[0-9.]+ MB/S DOWN$")) and .releases.header == "STARTING"'

# Continue watching resumes straight away, with no list.
wtype -k Escape
until_ok 1000 dekho_is '.page == "home"'
wtype kh
until_ok 1000 dekho_is '.focus == {"row": "continue", "col": 0}'
wtype -k Return
until_ok 3000 unit_active
note_session
check "Enter on Continue watching starts the unit with no release list ($(dekho_state | jq -c '[.page, .releases.mode]'))" \
  bash -c "systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && timeout 0.5 qs ipc -p '$dekho_qml' call dekho state | jq -e '.page == \"home\" and .releases.mode == \"starting\"' >/dev/null"
check "the fake was asked to play The Long Tide with --resume" grep -qx 'play --json --id 101 --kind tv --resume' "$fake_log"
until_ok 6000 dekho_is '.releases.mode == "" and .releases.playing != null'
wtype -k Escape
until_ok 3000 dekho_gone
check "esc on Home closes Dekho" dekho_gone
check "and the unit plays on with Dekho closed" unit_active

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
