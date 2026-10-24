#!/usr/bin/env bash
# Dekho on the real dekho backend, pointed at the backend's fake services: search the series, play S1 E1's release in mpv, quit it at about 10 s, and Continue watching resumes it within 2 s of where it stopped.
{
# The nested App and its units run on this machine's real user manager, so this run's unit has a name of its own, set before lib.sh starts the session that inherits it.
export DOTS_DEKHO_UNIT=dekho-play-real-$$
source "$(dirname "$0")/lib.sh"

backend=/home/saiful/Codes/dekho
dekho_bin=$backend/target/debug/dekho
fake_bin=$backend/target/debug/examples/fake_services
dekho_qml=$repo/shell/dekho.qml
work=$(mktemp -d)
runtime=${XDG_RUNTIME_DIR:-/tmp}/dekho
sessions=$work/sessions
log=$work/dekho.log
fake_pid=
cleanup() {
  systemctl --user stop "$DOTS_DEKHO_UNIT.service" 2>/dev/null
  [ -z "$fake_pid" ] || { kill "$fake_pid" 2>/dev/null; wait "$fake_pid" 2>/dev/null; }
  [ -f "$sessions" ] && xargs -r rm -f <"$sessions"
  rm -f "$runtime/$DOTS_DEKHO_UNIT.log" "$runtime/$DOTS_DEKHO_UNIT.session"
  rm -rf "$work"
}

if ! cargo build --offline -q --manifest-path "$backend/Cargo.toml" --bin dekho --example fake_services; then
  echo "FAIL the backend at $backend builds"
  exit 1
fi
mkdir -p "$work"/{config,cache,state,mpv}
# Dekho's theme lives under XDG_STATE_HOME, so the temp state dir keeps the nested session's.
ln -s "$DOTS_DEV_DIR/state/dots" "$work/state/dots"
printf 'ao=null\n' >"$work/mpv/mpv.conf"
# dekho never resumes within 60 s of the end, so the clip runs 120 s for a stop at 10 s to resume.
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=duration=120:size=640x360:rate=25 \
  -f lavfi -i sine=frequency=440:duration=120 -c:v libx264 -preset ultrafast -c:a aac -shortest "$work/clip.mkv"
# The seeder sends 1.5 MB a second, so the 3.8 MB clip buffers over about 3 s and Starting is drawn long enough to read.
"$fake_bin" --clip "$work/clip.mkv" --series --upload-bps 1500000 >"$work/hello" 2>"$work/fake.log" &
fake_pid=$!
until_ok 30000 test -s "$work/hello"
base=$(jq -r .base "$work/hello")
peer=$(jq -r .peer "$work/hello")
check "fake_services seeds the clip and serves TMDB, Torrentio and apibay on loopback ($(cat "$work/hello"))" \
  bash -c "[[ '$base' == http://127.0.0.1:* && '$peer' == 127.0.0.1:* ]]"

env_line="DOTS_DEKHO=$dekho_bin DOTS_DEKHO_UNIT=$DOTS_DEKHO_UNIT TMDB_API_KEY=fake-key DEKHO_TMDB_URL=$base DEKHO_TMDB_IMAGE_URL=$base DEKHO_TORRENTIO_URL=$base DEKHO_APIBAY_URL=$base DEKHO_PEERS=$peer DEKHO_NO_DHT=1 XDG_CONFIG_HOME=$work/config XDG_CACHE_HOME=$work/cache XDG_STATE_HOME=$work/state MPV_HOME=$work/mpv"
open_dekho() { niri msg action spawn -- sh -c "exec env $env_line '$repo/bin/dots-dekho' >>'$log' 2>&1"; }

dekho_state() { timeout 0.5 qs ipc -p "$dekho_qml" call dekho state 2>/dev/null; }
dekho_is() { dekho_state | jq -e "$@" >/dev/null 2>&1; }
window_of() { niri msg -j windows | jq -r --arg a "$1" 'first(.[] | select(.app_id == $a) | "\(.id) \(.pid)") // empty'; }
dekho_up() { [ -n "$(window_of dekho)" ] && dekho_is '.firstFrameMs != null'; }
dekho_gone() { [ -z "$(window_of dekho)" ]; }
mpv_up() { [ -n "$(window_of mpv)" ]; }
unit_active() { systemctl --user is-active --quiet "$DOTS_DEKHO_UNIT.service"; }
unit_inactive() { ! unit_active; }
gone() { [ -n "$1" ] && ! kill -0 "$1" 2>/dev/null; }
history_item() { jq -c '.items[0] | {id, season, episode, position, duration, finished}' "$work/state/dekho/history.json" 2>/dev/null; }
session_event() { jq -c --arg e "$1" 'select(.event == $e)' "$session" 2>/dev/null | head -1; }
note_session() { session=$(dekho_state | jq -r .releases.session); echo "$session" >>"$sessions"; }

# Starting is read every 50 ms from Enter until playing: the step names and the release it tries, as drawn.
watch_starting() {
  local s deadline=$(($(now_ms) + 15000))
  : >"$work/steps"
  release=
  while (($(now_ms) < deadline)); do
    s=$(dekho_state)
    jq -e '.releases.playing != null' <<<"$s" >/dev/null 2>&1 && break
    if jq -e '.releases.mode == "starting"' <<<"$s" >/dev/null 2>&1; then
      jq -r '.releases.starting.steps[].text' <<<"$s" >>"$work/steps"
      [ -n "$release" ] || release=$(jq -r .releases.starting.release <<<"$s")
    fi
    sleep 0.05
  done
  steps=$(awk '!seen[$0]++' "$work/steps" | paste -sd '|')
}

# Closing mpv's window quits it; dekho saves the position, and the unit ends with mpv.
quit_mpv() {
  local t0
  read -r mpv_win mpv_pid <<<"$(window_of mpv)"
  dekho_pid=$(systemctl --user show -p MainPID --value "$DOTS_DEKHO_UNIT.service")
  niri msg action close-window --id "$mpv_win"
  t0=$(now_ms)
  until_ok 3000 unit_inactive
  quit_ms=$(($(now_ms) - t0))
}

open_dekho
until_ok 15000 dekho_up
until_ok 5000 dekho_is '(.rows.series | length) > 0'
check "Dekho opens on the real backend's trending rows ($(dekho_state | jq -c '[.rows.series[].title]'))" \
  dekho_is '[.rows.series[].title] | index("Test Pattern Show") != null'

wtype /
until_ok 1000 dekho_is '.focus.row == "search"'
wtype 'Test Pattern Show'
wtype -k Return
until_ok 5000 dekho_is '(.search.results | length) == 2'
check "searching the series draws the fake TMDB's hits ($(dekho_state | jq -c '[.search.results[] | [.title, .line]]'))" \
  dekho_is '[.search.results[].title] == ["Test Pattern", "Test Pattern Show"]'
wtype l
until_ok 1000 dekho_is '.focus == {"row": "results", "col": 1}'
wtype -k Return
until_ok 5000 dekho_is '.page == "title" and (.title.episodes | length) == 2'
check "Enter on it opens its page on S1 E1, next up ($(dekho_state | jq -c '[.title.name, .title.season, .title.cursor, [.title.episodes[].name]]'))" \
  dekho_is '.title.name == "Test Pattern Show" and .title.season == 1 and .title.cursor == 1'
wtype -k Return
until_ok 8000 dekho_is '.releases.mode == "list" and (.releases.rows | length) == 1'
check "Enter on S1 E1 lists the fake Torrentio's one release ($(dekho_state | jq -c '[.releases.heading, (.releases.rows[] | [.quality, .size, .seeders])]'))" \
  dekho_is '.releases.rows[0] | .quality == "720p" and .size == "3.8 MB" and .seeders == "25"'

t0=$(now_ms)
wtype -k Return
watch_starting
play_ms=$(($(now_ms) - t0))
note_session
check "Enter on the release starts the unit and Starting draws the real events: $release, steps $steps" \
  test "$release|$steps" = "720p · 3.8 MB|Found 25 seeders|Connected to peers|Buffering the start of the file|mpv starts at 3.8 MB"
check "dekho says playing, ${play_ms} ms after Enter ($(session_event playing))" \
  dekho_is '.releases.playing.event == "playing" and .releases.playing.id == 900002 and .releases.mode == ""'
until_ok 10000 mpv_up
check "mpv opens its window by itself in the nested session ($(window_of mpv))" mpv_up
check "the test unit $DOTS_DEKHO_UNIT runs it" unit_active

# About 10 s of play, from the window's map.
sleep 10
quit_mpv
check "closing mpv's window ends the unit in ${quit_ms} ms, within 3 s" unit_inactive
check "and leaves no dekho (pid $dekho_pid) or mpv (pid $mpv_pid) of it" bash -c "[ '${dekho_pid:-0}' -gt 0 ] && [ '${mpv_pid:-0}' -gt 0 ] && ! kill -0 '$dekho_pid' 2>/dev/null && ! kill -0 '$mpv_pid' 2>/dev/null"
check "dekho says mpv quit ($(session_event ended))" bash -c "jq -e 'select(.event == \"ended\") | .reason == \"quit\"' '$session' >/dev/null"
saved=$(history_item)
check "history.json holds S1 E1 at about 10 s, not finished ($saved)" \
  bash -c "jq -e '.id == 900002 and .season == 1 and .episode == 1 and .position >= 8 and .position <= 13 and .finished == false' <<<'$saved' >/dev/null"
position=$(jq .position <<<"$saved")
# An empty piece cache, so the resume streams again and Starting is drawn on the way.
rm -rf "$work/cache/dekho"

read -r _ qs_pid <<<"$(window_of dekho)"
niri msg action close-window --id "$(window_of dekho | cut -d' ' -f1)"
until_ok 3000 dekho_gone
until_ok 3000 gone "$qs_pid"
check "closing Dekho ends its qs (pid $qs_pid)" gone "$qs_pid"

open_dekho
until_ok 15000 dekho_up
until_ok 5000 dekho_is '(.rows.continue | length) > 0'
check "reopened, Continue watching's first card is the series at S1 E1 with its time left ($(dekho_state | jq -c '.rows.continue[0] | [.title, .line, .progress]'))" \
  dekho_is '.focus == {"row": "continue", "col": 0} and .rows.continue[0].title == "Test Pattern Show" and .rows.continue[0].line == "S1 E1 · 2 min left"'
t0=$(now_ms)
wtype -k Return
watch_starting
resume_ms=$(($(now_ms) - t0))
note_session
playing=$(session_event playing)
check "Enter on it goes through Starting ($release, steps $steps) to playing in ${resume_ms} ms ($playing)" \
  bash -c "[ '$release' = '720p · 3.8 MB' ] && jq -e '.event == \"playing\"' <<<'$playing' >/dev/null"
check "and resumes within 2 s of $position s, where it stopped (resumed_at $(jq .resumed_at <<<"$playing"))" \
  bash -c "jq -e --argjson p '$position' '(.resumed_at - \$p) | fabs <= 2' <<<'$playing' >/dev/null"
until_ok 10000 mpv_up
check "mpv's window maps again ($(window_of mpv))" mpv_up

quit_mpv
check "closing mpv ends the unit in ${quit_ms} ms, with no dekho (pid $dekho_pid) or mpv (pid $mpv_pid) left" \
  bash -c "! systemctl --user is-active --quiet '$DOTS_DEKHO_UNIT.service' && ! kill -0 '${dekho_pid:-0}' 2>/dev/null && ! kill -0 '${mpv_pid:-0}' 2>/dev/null"
read -r _ qs_pid <<<"$(window_of dekho)"
wtype -k Escape
until_ok 3000 dekho_gone
until_ok 3000 gone "$qs_pid"
check "esc on Home closes Dekho and its qs (pid $qs_pid) ends" gone "$qs_pid"
check "no qs runs $dekho_qml" bash -c "! timeout 0.5 qs ipc -p '$dekho_qml' call dekho state >/dev/null 2>&1"

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable|Binding loop' "$log")
check "Dekho's log has no QML errors${errs:+: $(head -c 200 <<<"$errs")}" test -z "$errs"
echo "timings: Enter to playing ${play_ms} ms, resume Enter to playing ${resume_ms} ms, quit to unit inactive ${quit_ms} ms"

exit $((fails > 0))
}
