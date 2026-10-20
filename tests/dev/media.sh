#!/usr/bin/env bash
# Now playing: the island rests as the track while an MPRIS player plays, and as the clock once it pauses.
{
source "$(dirname "$0")/lib.sh"

until_ok 5000 shell_status >/dev/null
island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
mode_is() { island | jq -e --arg m "$1" '.mode == $m' >/dev/null 2>&1; }

"$repo/bin/dev-fake-mpris" Track Artist &
player=$!
cleanup() { kill "$player" 2>/dev/null; }
until_ok 3000 mode_is playing
echo "     island: $(island)"
shows_track() { island | jq -e --arg t "Track — Artist  $(date +%H:%M)" '.text == $t' >/dev/null; }
check "a playing player rests the island as Track — Artist beside the clock" shows_track

busctl --user call org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Pause
until_ok 2000 mode_is rest
clock_only() { island | jq -e --arg t "$(date +%H:%M)" '.text == $t' >/dev/null; }
check "after pause the island shows the clock only" clock_only

busctl --user call org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Play
until_ok 2000 mode_is playing
notify-send hi
until_ok 1000 mode_is notification
check "a notification outranks now playing" mode_is notification
until_ok 6000 mode_is playing
check "and the island goes back to now playing after it" mode_is playing
# The media keys reach the player through the shell: Play/Pause toggles it, and Next and Previous move it.
media() { niri msg action spawn -- dots-call media "$1"; }
title_is() { island | jq -e --arg t "$1 — Artist  $(date +%H:%M)" '.text == $t' >/dev/null; }
media playPause
until_ok 2000 mode_is rest
check "the Play/Pause key pauses the playing player" mode_is rest
# A paused player is the one Play resumes, though nothing plays.
media playPause
until_ok 2000 mode_is playing
check "and Play/Pause again resumes it" mode_is playing
media next
until_ok 2000 title_is Next
check "the Next key moves the player to the next track ($(island | jq -r .text))" title_is Next
media previous
until_ok 2000 title_is Previous
check "the Previous key moves it back ($(island | jq -r .text))" title_is Previous

status=$(shell_status)
one_timer() { jq -e '.timers == 1' <<<"$status" >/dev/null; }
check "playing media runs no timer" one_timer

exit $((fails > 0))
}
