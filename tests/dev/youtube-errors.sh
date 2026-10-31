#!/usr/bin/env bash
# A failed YouTube search shows the error boards' block in the list, the CLI's own fix line and yt-dlp's raw line under YouTube didn't give results, never an empty list, and Enter on it searches again; the real CLI with no deno on hand answers the runtime line before yt-dlp runs.
{
source "$(dirname "$0")/lib.sh"

yt_qml=$repo/shell/youtube.qml
work=$(mktemp -d)
cleanup() {
  systemctl --user stop 'youtube-video-*' 2>/dev/null
  rm -f "$DOTS_DEV_DIR/youtube-fail"
  rm -rf "$work"
}
log=$work/youtube.log
calls=$DOTS_DEV_DIR/youtube.log

yt_state() { timeout 0.5 qs ipc -p "$yt_qml" call youtube state 2>/dev/null; }
yt_is() { yt_state | jq -e "$@" >/dev/null 2>&1; }
yt_windows() { niri msg -j windows | jq '[.[] | select(.app_id == "youtube")] | length'; }
yt_up() { [ "$(yt_windows)" = 1 ] && yt_is '.firstFrameMs != null'; }
yt_gone() { [ "$(yt_windows)" = 0 ]; }
status_theme() { shell_status | jq -e --arg t "$1" '.theme == $t and .transition == ""' >/dev/null; }
searches() { grep -c '^search nujabes videos 0$' "$calls" 2>/dev/null; }
searched() { [ "$(searches)" = "$1" ]; }
fails_with() { yt_is --arg e "$1" '.failed.fix == $e'; }

"$repo/bin/dots" theme paper >/dev/null
until_ok 3000 status_theme paper
# The nested session's XDG_STATE_HOME is scratch already and holds the theme the App draws in, so only data and cache move.
exec_line="env DOTS_DEV_DIR=$DOTS_DEV_DIR DOTS_YOUTUBE=$repo/bin/dev-fake-youtube DOTS_YOUTUBE_MPV=$repo/dev/youtube/mpv $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up

runtime='yt-dlp needs deno 2.3 or newer: run dots update'
extraction='yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update'
network='No network. Check Wi-Fi, then ↵ to try again.'

echo runtime >"$DOTS_DEV_DIR/youtube-fail"
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype nujabes
until_ok 1000 yt_is '.query == "nujabes"'
wtype -k Return
until_ok 3000 fails_with "$runtime"
check "runtime: the list holds the error block, not rows ($(yt_state | jq -c '{failed, drawn: (.drawn | length), focus}'))" \
  yt_is --arg e "$runtime" '.failed.head == "YouTube didn'"'"'t give results" and .failed.fix == $e and .failed.retry == "↵ try again" and .failed.raw == "" and .drawn == [] and .focus == "list"'
check "runtime: the state names the failure's kind ($(yt_state | jq -c .error))" yt_is '.error.kind == "runtime"'
check "runtime: the legend reads try again first ($(yt_state | jq -c '.look.legend'))" \
  yt_is '.look.legend == ["↵ TRY AGAIN", "/ SEARCH", "TAB SIDEBAR", "ESC BACK"]'

echo extraction >"$DOTS_DEV_DIR/youtube-fail"
wtype -k Return
until_ok 3000 fails_with "$extraction"
check "extraction: Enter on the block searched again ($(searches))" searched 2
check "extraction: the fix line sits above yt-dlp's raw line in small mono ($(yt_state | jq -c .failed))" \
  yt_is --arg e "$extraction" '.failed.fix == $e and .failed.raw == "ERROR: [youtube] Sign in to confirm you'"'"'re not a bot" and .failed.rawFont == "Maple Mono" and .failed.rawSize == 11 and .failed.rawBelow'
check "extraction: Paper heads the block YOUTUBE CHANGED ($(yt_state | jq -c .failed.kicker))" yt_is '.failed.kicker == "YOUTUBE CHANGED"'

echo network >"$DOTS_DEV_DIR/youtube-fail"
wtype -k Return
until_ok 3000 fails_with "$network"
check "network: the block reads the no-network line with try again, never an empty list ($(yt_state | jq -c '{failed, drawn: (.drawn | length)}'))" \
  yt_is --arg e "$network" '.failed.fix == $e and .failed.retry == "↵ try again" and .failed.head == "YouTube didn'"'"'t give results" and .failed.kicker == "" and .drawn == []'

rm -f "$DOTS_DEV_DIR/youtube-fail"
wtype -k Return
until_ok 3000 yt_is '(.rows | length) == 20'
check "with the fail file gone, Enter on the block searched again and lists 20 rows ($(searches) searches, $(yt_state | jq -c '{n: (.drawn | length), failed, legend: .look.legend[0]}'))" \
  yt_is '(.drawn | length) == 20 and .failed == null and .error == null and .look.legend[0] == "J/K MOVE"'
check "4 searches in all" searched 4

wtype -k Escape
until_ok 3000 yt_gone

# The real CLI on a PATH with no mise: it finds no deno, so it answers before yt-dlp, here a stub that marks a run, ever starts.
mkdir -p "$work/bin"
for t in bash sh env python3 qs niri jq pgrep readlink dirname; do ln -s "$(command -v "$t")" "$work/bin/$t"; done
printf '#!/bin/sh\ntouch %s/yt-dlp-ran\nexit 1\n' "$work" >"$work/bin/yt-dlp"
chmod +x "$work/bin/yt-dlp"
no_mise() { env PATH="$work/bin" python3 -c 'import shutil, sys; sys.exit(shutil.which("mise") is not None)'; }
check "the PATH holds no mise" no_mise
exec_line="env PATH=$work/bin DOTS_YOUTUBE=$repo/bin/dots-youtube-api $mise_dirs XDG_DATA_HOME=$work XDG_CACHE_HOME=$work $repo/bin/dots-youtube"
niri msg action spawn -- sh -c "exec $exec_line >>'$log' 2>&1"
until_ok 5000 yt_up
wtype /
until_ok 1000 yt_is '.focus == "field"'
wtype lofi
until_ok 1000 yt_is '.query == "lofi"'
wtype -k Return
until_ok 10000 fails_with "$runtime"
check "the real CLI with no deno shows the runtime line ($(yt_state | jq -c .failed))" yt_is --arg e "$runtime" '.failed.fix == $e and .error.kind == "runtime" and .drawn == []'
check "and yt-dlp never ran" test ! -e "$work/yt-dlp-ran"
wtype -k Escape
until_ok 3000 yt_gone

errs=$(grep -E 'TypeError|ReferenceError|SyntaxError|Failed to load|is not a type|Cannot assign|Unable to assign|Cannot read propert|unavailable' "$log")
check "YouTube's log has no QML errors${errs:+: $(head -c 300 <<<"$errs")}" test -z "$errs"

exit $((fails > 0))
}
