#!/usr/bin/env bash
# Mod+I gives the island the keyboard, Exclusive, and a click outside the island gives it back: the card stays, and the window clicked keeps what is typed next.
{
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/pointer.bash"

island() { timeout 0.5 qs ipc call island state 2>/dev/null; }
island_is() { island | jq -e "$@" >/dev/null 2>&1; }
keyboard_is() { niri msg -j layers | jq -e --arg k "$1" 'any(.[]; .namespace == "dots-surfaces" and .keyboard_interactivity == $k)' >/dev/null; }
mod_i() { niri msg action spawn -- dots-call island focus; until_ok 2000 keyboard_is Exclusive; sleep 0.3; }
spot() { timeout 0.5 qs ipc call island box "$1" 2>/dev/null | jq -r '"\((.x + .w / 2) | floor) \((.y + .h / 2) | floor)"'; }
status_is() { busctl --user get-property org.mpris.MediaPlayer2.dotsfake /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | grep -qx "s \"$1\""; }
typed=$DOTS_DEV_DIR/typed
cleanup() { kill "$player" 2>/dev/null; }

until_ok 3000 island_is '.mode == "rest"'
notify-send -t 0 -A ok=OK "Deploy?"
until_ok 3000 island_is '.mode == "notification" and .animating == false'
mod_i
check "Mod+I on a notification card makes the window's keyboard Exclusive and focused true" bash -c "$(declare -f keyboard_is island island_is); keyboard_is Exclusive && island_is '.focused'"
point click 200 900
until_ok 2000 keyboard_is None
check "a click on the paper sets it to None and focused false" bash -c "$(declare -f keyboard_is island island_is); keyboard_is None && island_is '.focused == false'"
check "and the card stays" island_is '.mode == "notification"'
mod_i
wtype -k Escape
until_ok 3000 island_is '.mode == "rest"'

# A foot that reads what is typed into a file, then a playing track whose card is opened by a click.
niri msg action spawn -- foot -c /dev/null sh -c "cat > '$typed'"
until_ok 5000 bash -c '[ "$(niri msg -j focused-window | jq -r .app_id)" = foot ]'
niri msg action maximize-column
"$repo/bin/dev-fake-mpris" Track Artist &
player=$!
until_ok 3000 island_is '.mode == "playing" and .animating == false'
# shellcheck disable=SC2046
point click $(spot island)
until_ok 3000 island_is '.mode == "mediaCard" and .animating == false'
until_ok 2000 keyboard_is Exclusive
until_ok 2000 eval '[ "$(spot media:playPause)" != "" ]'
# shellcheck disable=SC2046
point click $(spot media:playPause)
until_ok 2000 status_is Paused
check "a click on the media card's pause pauses the player" status_is Paused
point click 400 1100
until_ok 2000 keyboard_is None
sleep 0.3
wtype "a b"
wtype -k Return
until_ok 2000 grep -q "a b" "$typed"
check "after a click in the foot, what is typed reaches the foot ($(cat "$typed" 2>/dev/null))" grep -qx "a b" "$typed"
check "and the player stays paused" status_is Paused
exit "$fails"
}
